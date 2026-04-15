<#
.SYNOPSIS
    Generative AI Config Auditor Dataverse client module.

.DESCRIPTION
    Provides helper functions for Dataverse interaction with the GAC solution.
    Follows the proven CMMClient pattern with GAC_ environment variable prefix.

    Tables:
    - fsi_gacbaselines: Agent generative AI configuration snapshots
    - fsi_gacvalidationhistory: Immutable audit trail of validation runs
    - fsi_gacviolations: Individual policy violations per agent/feature
    - fsi_gacapprovedconnections: Approved Azure OpenAI connection whitelist

.NOTES
    Module: GACClient.psm1
    Version: 1.0.0
    Requires: PowerShell 7.0+
    Author: FSI Agent Governance Team
#>

#requires -Version 7.0

#region Module Variables

$script:DataverseUrl = $null
$script:AccessToken = $null

# Zone string-to-integer mapping for Dataverse picklist column (fsi_zone option set)
$script:ZoneToInt = @{
    'Unknown' = 0
    'Zone1'   = 1
    'Zone2'   = 2
    'Zone3'   = 3
}
$script:IntToZone = @{
    0 = 'Unknown'
    1 = 'Zone1'
    2 = 'Zone2'
    3 = 'Zone3'
}

# Generative AI feature type picklist mapping
$script:GenAIFeatureTypeToInt = @{
    'AzureOpenAIIntegration' = 100000000
    'GenerativeOrchestration' = 100000001
    'GenerativeAnswersNode'  = 100000002
    'SearchAndSummarize'     = 100000003
    'GenerativeActions'      = 100000004
    'KnowledgeSource'        = 100000005
    'ModelKnowledge'         = 100000006
    'SemanticSearch'         = 100000007
}
$script:IntToGenAIFeatureType = @{
    100000000 = 'AzureOpenAIIntegration'
    100000001 = 'GenerativeOrchestration'
    100000002 = 'GenerativeAnswersNode'
    100000003 = 'SearchAndSummarize'
    100000004 = 'GenerativeActions'
    100000005 = 'KnowledgeSource'
    100000006 = 'ModelKnowledge'
    100000007 = 'SemanticSearch'
}

# Orchestration mode picklist mapping
$script:OrchestrationModeToInt = @{
    'Classic'    = 100000000
    'Generative' = 100000001
    'Custom'     = 100000002
}
$script:IntToOrchestrationMode = @{
    100000000 = 'Classic'
    100000001 = 'Generative'
    100000002 = 'Custom'
}

# Connection status picklist mapping
$script:ConnectionStatusToInt = @{
    'Approved'      = 100000000
    'Unapproved'    = 100000001
    'Unknown'       = 100000002
    'NotApplicable' = 100000003
}
$script:IntToConnectionStatus = @{
    100000000 = 'Approved'
    100000001 = 'Unapproved'
    100000002 = 'Unknown'
    100000003 = 'NotApplicable'
}

#endregion

#region Request Helper

function Invoke-DataverseRequest {
    <#
    .SYNOPSIS
        Wraps Invoke-RestMethod with retry/backoff for transient Dataverse errors.
    #>
    [CmdletBinding()]
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
            if ($Method -in @('Post', 'Patch') -and $Headers -and -not $Headers.ContainsKey('Content-Type')) {
                $params['ContentType'] = 'application/json'
            }
            return Invoke-RestMethod @params -ErrorAction Stop
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            # Retry on throttle (429) or server errors (5xx)
            if ($statusCode -in @(429, 500, 502, 503, 504) -and $i -lt ($MaxRetries - 1)) {
                $delay = [math]::Pow(2, $i)
                Write-Verbose "Dataverse request failed ($statusCode), retrying in ${delay}s..."
                Start-Sleep -Seconds $delay
                continue
            }
            throw
        }
    }
}

#endregion

#region Connection Functions

function Connect-GACDataverse {
    <#
    .SYNOPSIS
        Establishes connection to Dataverse for GAC operations.
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
            if ($token.Token -is [System.Security.SecureString]) {
                $script:AccessToken = $token.Token | ConvertFrom-SecureString -AsPlainText
            } else {
                $script:AccessToken = $token.Token
            }
            Write-Verbose "Acquired Dataverse token via Az.Accounts"
        } catch {
            Write-Warning "No access token provided and Az.Accounts token acquisition failed. Use Connect-EnvironmentDataverse for authenticated access."
        }
    }

    Write-Verbose "Connected to Dataverse: $script:DataverseUrl"
}

function Get-GACConnection {
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

function Get-GACEnvironmentVariable {
    <#
    .SYNOPSIS
        Retrieves GAC environment variable value from Dataverse.

    .PARAMETER Name
        Variable name (without fsi_GAC_ prefix).

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
        $schemaName = "fsi_GAC_$Name"
        $uri = "$script:DataverseUrl/api/data/v9.2/environmentvariabledefinitions?" +
               "`$filter=schemaname eq '$schemaName'&" +
               "`$expand=environmentvariablevalues"

        $headers = @{
            'Authorization'    = "Bearer $script:AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Get -Headers $headers

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

function Get-GACBaseline {
    <#
    .SYNOPSIS
        Retrieves generative AI configuration baseline records from Dataverse.

    .PARAMETER EnvironmentId
        Optional environment GUID to filter by.

    .PARAMETER AgentId
        Optional agent ID to filter by.

    .PARAMETER ActiveOnly
        When specified, returns only active baselines (fsi_isactive eq true).
        Use with no other filters to batch-query all active baselines for
        hashtable construction in drift detection.
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
        $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
        $filter = "statecode eq 0"
        if ($EnvironmentId) {
            if ($EnvironmentId -notmatch $guidPattern) {
                throw "EnvironmentId '$EnvironmentId' is not a valid GUID format."
            }
            $filter += " and fsi_environmentguid eq '$EnvironmentId'"
        }
        if ($AgentId) {
            if ($AgentId -notmatch $guidPattern) {
                throw "AgentId '$AgentId' is not a valid GUID format."
            }
            $filter += " and fsi_agentid eq '$AgentId'"
        }
        if ($ActiveOnly) {
            $filter += " and fsi_isactive eq true"
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_gacbaselines?" +
               "`$filter=$filter&`$orderby=createdon desc"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Accept'        = 'application/json'
        }

        $allRecords = @()
        $nextLink = $uri

        while ($nextLink) {
            $response = Invoke-DataverseRequest -Uri $nextLink -Method Get -Headers $headers
            $allRecords += $response.value
            $nextLink = $response.'@odata.nextLink'
        }

        # Map Dataverse fields to friendly property names
        return $allRecords | ForEach-Object {
            # Convert picklist integer back to zone string
            $zoneValue = $_.fsi_zone
            $zoneName = if ($null -ne $zoneValue -and $script:IntToZone.ContainsKey([int]$zoneValue)) {
                $script:IntToZone[[int]$zoneValue]
            } else { 'Unknown' }

            # Convert orchestration mode integer back to string
            $orchValue = $_.fsi_orchestrationmode
            $orchName = if ($null -ne $orchValue -and $script:IntToOrchestrationMode.ContainsKey([int]$orchValue)) {
                $script:IntToOrchestrationMode[[int]$orchValue]
            } else { 'Unable to Determine' }

            [PSCustomObject]@{
                BaselineId                 = $_.fsi_gacbaselineid
                Name                       = $_.fsi_name
                EnvironmentGuid            = $_.fsi_environmentguid
                EnvironmentName            = $_.fsi_environmentname
                Zone                       = $zoneName
                AgentId                    = $_.fsi_agentid
                AgentName                  = $_.fsi_agentname
                AzureOpenAIEnabled         = $_.fsi_aoaienabled
                OrchestrationMode          = $orchName
                KnowledgeSourceCount       = $_.fsi_knowledgesourcecount
                GenerativeAnswersNodeCount = $_.fsi_generativeanswersnodecount
                AoaiConnectionId           = $_.fsi_aoaiconnectionid
                CapturedBy                 = $_.fsi_capturedby
                CapturedAt                 = $_.fsi_capturedat
                IsActive                   = $_.fsi_isactive
                RawJson                    = $_.fsi_rawjson
            }
        }
    } catch {
        Write-Warning "Failed to get GAC baseline: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Validation History Functions

function Write-GACValidationHistory {
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
            fsi_name                 = "$($ValidationResult.OverallStatus)-$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
            fsi_runid                = $RunId
            fsi_validationtime       = (Get-Date).ToUniversalTime().ToString('o')
            fsi_totalagents          = $ValidationResult.TotalAgents
            fsi_compliantcount       = $ValidationResult.CompliantCount
            fsi_violationcount       = $ValidationResult.ViolationCount
            fsi_overallstatus        = $ValidationResult.OverallStatus
            fsi_environmentsscanned  = $ValidationResult.EnvironmentsScanned
            fsi_summaryjson          = ($ValidationResult | ConvertTo-Json -Depth 10 -Compress)
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_gacvalidationhistory"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
        Write-Verbose "GAC validation history record created"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write validation history (audit trail gap): $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Violation Functions

function Write-GACViolation {
    <#
    .SYNOPSIS
        Writes generative AI configuration violation record to Dataverse.

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
        # Convert zone string to picklist integer for Dataverse
        $zoneInt = if ($script:ZoneToInt.ContainsKey($Violation.Zone)) {
            $script:ZoneToInt[$Violation.Zone]
        } else { 0 }

        # Convert feature type string to picklist integer for Dataverse
        $featureTypeInt = if ($Violation.FeatureType -and $script:GenAIFeatureTypeToInt.ContainsKey($Violation.FeatureType)) {
            $script:GenAIFeatureTypeToInt[$Violation.FeatureType]
        } else { $null }

        # Convert connection status string to picklist integer for Dataverse
        $connectionStatusInt = if ($Violation.ConnectionStatus -and $script:ConnectionStatusToInt.ContainsKey($Violation.ConnectionStatus)) {
            $script:ConnectionStatusToInt[$Violation.ConnectionStatus]
        } else { $null }

        $record = @{
            fsi_name              = "$($Violation.AgentName)-$($Violation.FeatureType)-$(Get-Date -Format 'yyyy-MM-dd')"
            fsi_environmentguid   = $Violation.EnvironmentId
            fsi_environmentname   = $Violation.EnvironmentDisplayName
            fsi_agentid           = $Violation.AgentId
            fsi_agentname         = $Violation.AgentName
            fsi_zone              = $zoneInt
            fsi_expectedstate     = $Violation.ExpectedState
            fsi_actualstate       = $Violation.ActualState
            fsi_severity          = $Violation.Severity
            fsi_regulatorycontext = $Violation.RegulatoryContext
            fsi_detectedat        = (Get-Date).ToUniversalTime().ToString('o')
        }

        # Add feature type if resolved
        if ($null -ne $featureTypeInt) {
            $record['fsi_featuretype'] = $featureTypeInt
        }

        # Add connection status if resolved
        if ($null -ne $connectionStatusInt) {
            $record['fsi_connectionstatus'] = $connectionStatusInt
        }

        # Add optional topic fields
        if ($Violation.TopicName) {
            $record['fsi_topicname'] = $Violation.TopicName
        }
        if ($Violation.TopicId) {
            $record['fsi_topicid'] = $Violation.TopicId
        }

        if ($RunId) {
            $record['fsi_runid'] = $RunId
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_gacviolations"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
        Write-Verbose "GAC violation record created for $($Violation.AgentName) - $($Violation.FeatureType)"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write violation record for '$($Violation.AgentName)': $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Baseline Write Functions

function Save-GACBaseline {
    <#
    .SYNOPSIS
        Saves a generative AI configuration baseline record to Dataverse.

    .DESCRIPTION
        Captures current agent generative AI settings as a baseline. Deactivates
        any previous active baseline for the same agent before creating the new one.
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
        [bool]$AzureOpenAIEnabled,

        [Parameter(Mandatory)]
        [string]$OrchestrationMode,

        [Parameter()]
        [int]$KnowledgeSourceCount = 0,

        [Parameter()]
        [int]$GenerativeAnswersNodeCount = 0,

        [Parameter()]
        [string]$AoaiConnectionId,

        [Parameter()]
        [string]$CapturedBy,

        [Parameter()]
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

        # Validate GUID format to prevent OData injection
        $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
        if ($AgentId -notmatch $guidPattern) {
            throw "AgentId '$AgentId' is not a valid GUID format."
        }

        # Deactivate existing active baseline for this agent
        $deactivateFilter = "fsi_isactive eq true and fsi_agentid eq '$AgentId'"
        $queryUri = "$script:DataverseUrl/api/data/v9.2/fsi_gacbaselines?`$filter=$deactivateFilter&`$select=fsi_gacbaselineid"

        $existing = Invoke-DataverseRequest -Uri $queryUri -Method Get -Headers $headers

        foreach ($prev in $existing.value) {
            $prevId = $prev.fsi_gacbaselineid
            if ($PSCmdlet.ShouldProcess("Baseline $prevId for $AgentName", "Deactivate previous active baseline")) {
                $patchUri = "$script:DataverseUrl/api/data/v9.2/fsi_gacbaselines($prevId)"
                $patchBody = @{ fsi_isactive = $false } | ConvertTo-Json
                Invoke-DataverseRequest -Uri $patchUri -Method Patch -Body $patchBody -Headers $headers | Out-Null
                Write-Verbose "Deactivated previous baseline: $prevId"
            }
        }

        # Create new active baseline
        $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        $capturedByValue = if ($CapturedBy) { $CapturedBy } else { "System" }
        $rawJsonValue = if ($RawJson) { $RawJson } else { "" }

        # Convert zone string to picklist integer for Dataverse
        $zoneInt = if ($script:ZoneToInt.ContainsKey($Zone)) {
            $script:ZoneToInt[$Zone]
        } else { 0 }

        # Convert orchestration mode to picklist integer
        $orchInt = if ($script:OrchestrationModeToInt.ContainsKey($OrchestrationMode)) {
            $script:OrchestrationModeToInt[$OrchestrationMode]
        } else { $null }

        $record = @{
            fsi_name                       = "$AgentName-$Zone-$timestamp"
            fsi_environmentguid            = $EnvironmentGuid
            fsi_environmentname            = $EnvironmentName
            fsi_zone                       = $zoneInt
            fsi_agentid                    = $AgentId
            fsi_agentname                  = $AgentName
            fsi_aoaienabled                = $AzureOpenAIEnabled
            fsi_knowledgesourcecount       = $KnowledgeSourceCount
            fsi_generativeanswersnodecount = $GenerativeAnswersNodeCount
            fsi_capturedby                 = $capturedByValue
            fsi_capturedat                 = $timestamp
            fsi_isactive                   = $true
            fsi_rawjson                    = $rawJsonValue
        }

        # Add orchestration mode if resolved
        if ($null -ne $orchInt) {
            $record['fsi_orchestrationmode'] = $orchInt
        }

        # Add AOAI connection ID if provided
        if ($AoaiConnectionId) {
            $record['fsi_aoaiconnectionid'] = $AoaiConnectionId
        }

        if ($PSCmdlet.ShouldProcess("$AgentName in $EnvironmentName ($Zone)", "Save generative AI config baseline")) {
            $uri = "$script:DataverseUrl/api/data/v9.2/fsi_gacbaselines"
            $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
            Write-Verbose "GAC baseline saved for $AgentName in $EnvironmentName ($Zone)"
            return $response
        }
    } catch {
        Write-Error "CRITICAL: Failed to save baseline for '$AgentName': $($_.Exception.Message)"
        throw
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
        - configuration: JSON blob containing bot configuration including generative AI settings
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
            $response = Invoke-DataverseRequest -Uri $nextLink -Method Get -Headers $headers
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

function Get-BotGenAISettings {
    <#
    .SYNOPSIS
        Extracts generative AI settings from a bot configuration record.

    .DESCRIPTION
        Parses the bot.configuration JSON blob and optional botsettings records to
        extract generative AI configuration. Looks for:
        - Azure OpenAI integration status
        - Orchestration mode (Classic / Generative / Custom)
        - Knowledge source count
        - AOAI connection identifier

        Uses conservative pattern matching. Returns 'Unable to Determine' for any
        setting that cannot be reliably extracted, rather than making assumptions.

    .PARAMETER Bot
        A bot record PSCustomObject from Get-AgentBots.

    .PARAMETER BotSettings
        Optional array of botsettings records for fallback lookup.

    .OUTPUTS
        PSCustomObject with:
        - AzureOpenAIEnabled (bool or $null)
        - OrchestrationMode (string)
        - KnowledgeSourceCount (int)
        - AoaiConnectionId (string or $null)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Bot,

        [Parameter()]
        [PSCustomObject[]]$BotSettings
    )

    $result = [PSCustomObject]@{
        AzureOpenAIEnabled   = $null
        OrchestrationMode    = 'Unable to Determine'
        KnowledgeSourceCount = 0
        AoaiConnectionId     = $null
    }

    # Try extracting from bot.configuration JSON blob
    if ($Bot.configuration) {
        try {
            $config = $Bot.configuration | ConvertFrom-Json -ErrorAction Stop

            # --- Azure OpenAI enabled ---
            foreach ($key in @('AzureOpenAI', 'azureOpenAI', 'AzureOpenAIEnabled', 'azureOpenAIEnabled', 'IsAzureOpenAIEnabled')) {
                if ($config.PSObject.Properties.Name -contains $key) {
                    $rawValue = $config.$key
                    if ($rawValue -is [PSCustomObject]) {
                        # Nested: { "enabled": true, "connectionId": "..." }
                        if ($rawValue.PSObject.Properties.Name -contains 'enabled') {
                            $result.AzureOpenAIEnabled = [bool]$rawValue.enabled
                        }
                        if ($rawValue.PSObject.Properties.Name -contains 'connectionId') {
                            $result.AoaiConnectionId = $rawValue.connectionId
                        }
                        if ($rawValue.PSObject.Properties.Name -contains 'connectionid') {
                            $result.AoaiConnectionId = $rawValue.connectionid
                        }
                    } elseif ($rawValue -is [bool]) {
                        $result.AzureOpenAIEnabled = $rawValue
                    } elseif ($rawValue -is [string]) {
                        $result.AzureOpenAIEnabled = $rawValue -eq 'true'
                    }
                    break
                }
            }

            # --- Orchestration mode ---
            foreach ($key in @('OrchestrationMode', 'orchestrationMode', 'OrchestrationType', 'orchestrationType')) {
                if ($config.PSObject.Properties.Name -contains $key) {
                    $rawValue = $config.$key
                    if ($rawValue -is [string]) {
                        $normalized = $rawValue.Trim()
                        # Map known values
                        $modeMap = @{
                            'classic'    = 'Classic'
                            'generative' = 'Generative'
                            'custom'     = 'Custom'
                            'unified'    = 'Generative'
                        }
                        $lower = $normalized.ToLower()
                        if ($modeMap.ContainsKey($lower)) {
                            $result.OrchestrationMode = $modeMap[$lower]
                        } else {
                            $result.OrchestrationMode = $normalized
                        }
                    } elseif ($rawValue -is [int]) {
                        if ($script:IntToOrchestrationMode.ContainsKey($rawValue)) {
                            $result.OrchestrationMode = $script:IntToOrchestrationMode[$rawValue]
                        }
                    }
                    break
                }
            }

            # --- Knowledge sources ---
            foreach ($key in @('KnowledgeSources', 'knowledgeSources', 'DataSources', 'dataSources')) {
                if ($config.PSObject.Properties.Name -contains $key) {
                    $rawValue = $config.$key
                    if ($rawValue -is [System.Collections.IEnumerable] -and $rawValue -isnot [string]) {
                        $result.KnowledgeSourceCount = @($rawValue).Count
                    } elseif ($rawValue -is [int]) {
                        $result.KnowledgeSourceCount = $rawValue
                    }
                    break
                }
            }

            # --- AOAI Connection ID (fallback paths) ---
            if (-not $result.AoaiConnectionId) {
                foreach ($key in @('AoaiConnectionId', 'aoaiConnectionId', 'AzureOpenAIConnectionId', 'azureOpenAIConnectionId')) {
                    if ($config.PSObject.Properties.Name -contains $key) {
                        $result.AoaiConnectionId = $config.$key
                        break
                    }
                }
            }

        } catch {
            Write-Verbose "Failed to parse configuration JSON for bot '$($Bot.name)': $($_.Exception.Message)"
        }
    }

    # Fallback: check botsettings records
    if ($BotSettings -and ($null -eq $result.AzureOpenAIEnabled -or $result.OrchestrationMode -eq 'Unable to Determine')) {
        foreach ($setting in $BotSettings) {
            if ($setting.content -or $setting.data) {
                $rawContent = if ($setting.content) { $setting.content } else { $setting.data }
                try {
                    $settingConfig = $rawContent | ConvertFrom-Json -ErrorAction Stop

                    # Try AOAI enabled from settings
                    if ($null -eq $result.AzureOpenAIEnabled) {
                        foreach ($key in @('AzureOpenAI', 'azureOpenAI', 'AzureOpenAIEnabled')) {
                            if ($settingConfig.PSObject.Properties.Name -contains $key) {
                                $rawValue = $settingConfig.$key
                                if ($rawValue -is [PSCustomObject] -and $rawValue.PSObject.Properties.Name -contains 'enabled') {
                                    $result.AzureOpenAIEnabled = [bool]$rawValue.enabled
                                } elseif ($rawValue -is [bool]) {
                                    $result.AzureOpenAIEnabled = $rawValue
                                }
                                break
                            }
                        }
                    }

                    # Try orchestration mode from settings
                    if ($result.OrchestrationMode -eq 'Unable to Determine') {
                        foreach ($key in @('OrchestrationMode', 'orchestrationMode')) {
                            if ($settingConfig.PSObject.Properties.Name -contains $key) {
                                $modeValue = $settingConfig.$key
                                if ($modeValue -is [string] -and $modeValue.Trim()) {
                                    $result.OrchestrationMode = $modeValue.Trim()
                                }
                                break
                            }
                        }
                    }

                } catch {
                    Write-Verbose "Failed to parse bot settings content for bot '$($Bot.name)'"
                }
            }
        }
    }

    Write-Verbose "GenAI settings for '$($Bot.name)': AOAI=$($result.AzureOpenAIEnabled), Orch=$($result.OrchestrationMode), KS=$($result.KnowledgeSourceCount)"
    return $result
}

#endregion

#region Validation Query Functions

function Get-GACLastValidation {
    <#
    .SYNOPSIS
        Retrieves recent validation history records from Dataverse.

    .DESCRIPTION
        Queries the fsi_gacvalidationhistory table ordered by timestamp descending.
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
        $select = "fsi_name,fsi_runid,fsi_overallstatus,fsi_violationcount,fsi_totalagents,fsi_summaryjson,fsi_validationtime"
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_gacvalidationhistory?" +
               "`$orderby=fsi_validationtime desc&`$top=$Top&`$select=$select"

        $headers = @{
            'Authorization'    = "Bearer $script:AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Get -Headers $headers

        if ($response.value.Count -gt 0) {
            return $response.value | ForEach-Object {
                [PSCustomObject]@{
                    Name           = $_.fsi_name
                    RunId          = $_.fsi_runid
                    OverallStatus  = $_.fsi_overallstatus
                    ViolationCount = $_.fsi_violationcount
                    TotalAgents    = $_.fsi_totalagents
                    SummaryJson    = $_.fsi_summaryjson
                    Timestamp      = $_.fsi_validationtime
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

#region Approved Connections Functions

function Get-ApprovedConnections {
    <#
    .SYNOPSIS
        Queries approved Azure OpenAI connection whitelist from Dataverse.

    .DESCRIPTION
        Returns records from the fsi_gacapprovedconnections table. These represent
        the approved Azure OpenAI connections that agents are permitted to use,
        optionally filtered by zone and active status.

    .PARAMETER Zone
        Optional zone filter (Zone1, Zone2, Zone3).

    .PARAMETER ActiveOnly
        When specified, returns only active (non-expired) connections.

    .OUTPUTS
        Array of PSCustomObject with: ConnectionId, ConnectionName, Zone,
        AoaiEndpoint, ApprovedBy, ExpiresAt, IsActive
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
        [string]$Zone,

        [Parameter()]
        [switch]$ActiveOnly
    )

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected"
        return @()
    }

    try {
        $filter = "statecode eq 0"
        if ($Zone) {
            $zoneInt = $script:ZoneToInt[$Zone]
            $filter += " and fsi_zone eq $zoneInt"
        }
        if ($ActiveOnly) {
            $filter += " and fsi_isactive eq true"
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_gacapprovedconnections?" +
               "`$filter=$filter&`$orderby=createdon desc"

        $headers = @{
            'Authorization'    = "Bearer $script:AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        $allRecords = @()
        $nextLink = $uri

        while ($nextLink) {
            $response = Invoke-DataverseRequest -Uri $nextLink -Method Get -Headers $headers
            $allRecords += $response.value
            $nextLink = $response.'@odata.nextLink'
        }

        return $allRecords | ForEach-Object {
            # Convert zone integer back to string
            $zoneValue = $_.fsi_zone
            $zoneName = if ($null -ne $zoneValue -and $script:IntToZone.ContainsKey([int]$zoneValue)) {
                $script:IntToZone[[int]$zoneValue]
            } else { 'Unknown' }

            [PSCustomObject]@{
                ConnectionId   = $_.fsi_gacapprovedconnectionid
                ConnectionName = $_.fsi_connectionname
                Zone           = $zoneName
                AoaiEndpoint   = $_.fsi_aoaiendpoint
                ApprovedBy     = $_.fsi_approvedby
                ExpiresAt      = $_.fsi_expiresat
                IsActive       = $_.fsi_isactive
            }
        }
    } catch {
        Write-Warning "Failed to get approved connections: $($_.Exception.Message)"
        return @()
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Invoke-DataverseRequest',
    'Connect-GACDataverse',
    'Get-GACConnection',
    'Get-GACEnvironmentVariable',
    'Get-GACBaseline',
    'Write-GACValidationHistory',
    'Write-GACViolation',
    'Save-GACBaseline',
    'Get-AgentBots',
    'Get-BotGenAISettings',
    'Get-GACLastValidation',
    'Get-ApprovedConnections'
)
