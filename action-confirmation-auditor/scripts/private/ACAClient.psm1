<#
.SYNOPSIS
    Action Confirmation Auditor Dataverse client module.

.DESCRIPTION
    Provides helper functions for Dataverse interaction with the ACA solution.
    Follows the proven GACClient pattern with ACA_ environment variable prefix.

    Tables:
    - fsi_actionauditresults: Individual action confirmation audit findings per agent/action
    - fsi_actionscanrun: Immutable audit trail of scan run summaries
    - fsi_actionconfirmationexceptions: Approved exception records for specific actions

.EXAMPLE
    Import-Module .\ACAClient.psm1
    Connect-ACADataverse -DataverseUrl "https://org.crm.dynamics.com"
    $history = Get-ACALastValidation -Top 5

.NOTES
    Module: ACAClient.psm1
    Version: 1.0.2
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

# Action type picklist mapping
$script:ActionTypeToInt = @{
    'ConnectorAction' = 100000000
    'CloudFlowAction' = 100000001
    'PluginAction'    = 100000002
    'CustomAction'    = 100000003
    'HttpRequest'     = 100000004
}
$script:IntToActionType = @{
    100000000 = 'ConnectorAction'
    100000001 = 'CloudFlowAction'
    100000002 = 'PluginAction'
    100000003 = 'CustomAction'
    100000004 = 'HttpRequest'
}

# Confirmation status picklist mapping
$script:ConfirmationStatusToInt = @{
    'Present'            = 100000000
    'Missing'            = 100000001
    'Partial'            = 100000002
    'UnableToDetermine'  = 100000003
}
$script:IntToConfirmationStatus = @{
    100000000 = 'Present'
    100000001 = 'Missing'
    100000002 = 'Partial'
    100000003 = 'UnableToDetermine'
}

# Violation status picklist mapping
$script:ViolationStatusToInt = @{
    'Open'         = 100000000
    'Acknowledged' = 100000001
    'Excepted'     = 100000002
    'Resolved'     = 100000003
}
$script:IntToViolationStatus = @{
    100000000 = 'Open'
    100000001 = 'Acknowledged'
    100000002 = 'Excepted'
    100000003 = 'Resolved'
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

function Connect-ACADataverse {
    <#
    .SYNOPSIS
        Establishes connection to Dataverse for ACA operations.
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
            $script:DataverseUrl = $null
            return
        }
    }

    Write-Verbose "Connected to Dataverse: $script:DataverseUrl"
}

function Get-ACAConnection {
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

function Get-ACAEnvironmentVariable {
    <#
    .SYNOPSIS
        Retrieves ACA environment variable value from Dataverse.

    .PARAMETER Name
        Variable name (without fsi_ACA_ prefix).

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
        $schemaName = "fsi_ACA_$Name"
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

#region Scan Run Functions

function Write-ACAValidationHistory {
    <#
    .SYNOPSIS
        Writes immutable scan run record to Dataverse.

    .PARAMETER ValidationResult
        Hashtable containing scan run summary metrics including:
        - TotalActions: Total actions discovered across all agents
        - ActionsWithConfirmation: Actions that have confirmation configured
        - ActionsMissingConfirmation: Actions missing required confirmation
        - OverallStatus: Summary status string
        - EnvironmentsScanned: Count of environments scanned

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
        Write-Warning "Dataverse not connected, skipping scan run write"
        return $null
    }

    try {
        $record = @{
            fsi_name                        = "$($ValidationResult.OverallStatus)-$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
            fsi_runid                       = $RunId
            fsi_validationtime              = (Get-Date).ToUniversalTime().ToString('o')
            fsi_totalagents                 = $ValidationResult.TotalAgents
            fsi_totalactions                = $ValidationResult.TotalActions
            fsi_actionswithconfirmation     = $ValidationResult.ActionsWithConfirmation
            fsi_actionsmissingconfirmation  = $ValidationResult.ActionsMissingConfirmation
            fsi_violationcount              = $ValidationResult.ViolationCount
            fsi_overallstatus               = $ValidationResult.OverallStatus
            fsi_environmentsscanned         = $ValidationResult.EnvironmentsScanned
            fsi_summaryjson                 = ($ValidationResult | ConvertTo-Json -Depth 10 -Compress)
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_actionscanrun"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
        Write-Verbose "ACA scan run record created"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write scan run record (audit trail gap): $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Violation Functions

function Write-ACAViolation {
    <#
    .SYNOPSIS
        Writes action confirmation audit result record to Dataverse.

    .PARAMETER Violation
        Hashtable containing audit result details.

    .PARAMETER RunId
        Optional GUID correlating this result to a scan execution.
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

        # Convert action type string to picklist integer for Dataverse
        $actionTypeInt = if ($Violation.ActionType -and $script:ActionTypeToInt.ContainsKey($Violation.ActionType)) {
            $script:ActionTypeToInt[$Violation.ActionType]
        } else { $null }

        # Convert confirmation status string to picklist integer for Dataverse
        $confirmationStatusInt = if ($Violation.ConfirmationStatus -and $script:ConfirmationStatusToInt.ContainsKey($Violation.ConfirmationStatus)) {
            $script:ConfirmationStatusToInt[$Violation.ConfirmationStatus]
        } else { $null }

        # Convert violation status string to picklist integer for Dataverse
        $violationStatusInt = if ($Violation.ViolationStatus -and $script:ViolationStatusToInt.ContainsKey($Violation.ViolationStatus)) {
            $script:ViolationStatusToInt[$Violation.ViolationStatus]
        } else {
            $script:ViolationStatusToInt['Open']  # Default to Open
        }

        $record = @{
            fsi_name              = "$($Violation.AgentName)-$($Violation.ActionName)-$(Get-Date -Format 'yyyy-MM-dd')"
            fsi_environmentguid   = $Violation.EnvironmentId
            fsi_environmentname   = $Violation.EnvironmentDisplayName
            fsi_agentid           = $Violation.AgentId
            fsi_agentname         = $Violation.AgentName
            fsi_zone              = $zoneInt
            fsi_actionname        = $Violation.ActionName
            fsi_risklevel         = if ($Violation.ActionCategory) { $Violation.ActionCategory } else { 'Unknown' }
            fsi_severity          = $Violation.Severity
            fsi_regulatorycontext = $Violation.RegulatoryContext
            fsi_violationstatus   = $violationStatusInt
            fsi_detectedat        = (Get-Date).ToUniversalTime().ToString('o')
        }

        # Add action type if resolved
        if ($null -ne $actionTypeInt) {
            $record['fsi_actiontype'] = $actionTypeInt
        }

        # Add confirmation status if resolved
        if ($null -ne $confirmationStatusInt) {
            $record['fsi_confirmationstatus'] = $confirmationStatusInt
        }

        # Add optional topic fields
        if ($Violation.TopicName) {
            $record['fsi_topicname'] = $Violation.TopicName
        }
        if ($Violation.TopicId) {
            $record['fsi_topicid'] = $Violation.TopicId
        }

        # Add connector name if available
        if ($Violation.ConnectorName) {
            $record['fsi_connectorname'] = $Violation.ConnectorName
        }

        if ($RunId) {
            $record['fsi_runid'] = $RunId
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_actionauditresults"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
        Write-Verbose "ACA audit result record created for $($Violation.AgentName) - $($Violation.ActionName)"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write audit result record for '$($Violation.AgentName)': $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Scan Run Query Functions

function Get-ACALastValidation {
    <#
    .SYNOPSIS
        Retrieves recent scan run records from Dataverse.

    .DESCRIPTION
        Queries the fsi_actionscanrun table ordered by timestamp descending.
        Used to compare current scan results against previous runs.
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
        $select = "fsi_name,fsi_runid,fsi_overallstatus,fsi_totalactions,fsi_actionswithconfirmation,fsi_actionsmissingconfirmation,fsi_summaryjson,fsi_validationtime"
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_actionscanrun?" +
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
                    Name                       = $_.fsi_name
                    RunId                      = $_.fsi_runid
                    OverallStatus              = $_.fsi_overallstatus
                    TotalActions               = $_.fsi_totalactions
                    ActionsWithConfirmation     = $_.fsi_actionswithconfirmation
                    ActionsMissingConfirmation  = $_.fsi_actionsmissingconfirmation
                    SummaryJson                = $_.fsi_summaryjson
                    Timestamp                  = $_.fsi_validationtime
                }
            }
        }

        return $null
    } catch {
        Write-Warning "Failed to get scan run history: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Exception Functions

function Get-ActionConfirmationExceptions {
    <#
    .SYNOPSIS
        Queries approved action confirmation exceptions from Dataverse.

    .DESCRIPTION
        Returns records from the fsi_actionconfirmationexceptions table. These represent
        approved exceptions where specific actions are permitted to operate without
        user confirmation, optionally filtered by zone and agent.

    .PARAMETER Zone
        Optional zone filter (Zone1, Zone2, Zone3).

    .PARAMETER AgentId
        Optional agent ID to filter exceptions for a specific agent.

    .PARAMETER ActiveOnly
        When specified, returns only active (non-expired) exceptions.

    .OUTPUTS
        Array of PSCustomObject with: ExceptionId, ActionName, ActionType, AgentId,
        AgentName, Zone, ApprovedBy, Reason, ExpiresAt, IsActive
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
        [string]$Zone,

        [Parameter()]
        [string]$AgentId,

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
        if ($AgentId) {
            $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
            if ($AgentId -notmatch $guidPattern) {
                throw "AgentId '$AgentId' is not a valid GUID format."
            }
            $filter += " and fsi_agentid eq '$AgentId'"
        }
        if ($ActiveOnly) {
            $filter += " and fsi_isactive eq true"
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_actionconfirmationexceptions?" +
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

            # Convert action type integer back to string
            $actionTypeValue = $_.fsi_actiontype
            $actionTypeName = if ($null -ne $actionTypeValue -and $script:IntToActionType.ContainsKey([int]$actionTypeValue)) {
                $script:IntToActionType[[int]$actionTypeValue]
            } else { 'Unknown' }

            [PSCustomObject]@{
                ExceptionId = $_.fsi_actionconfirmationexceptionid
                ActionName  = $_.fsi_actionname
                ActionType  = $actionTypeName
                AgentId     = $_.fsi_agentid
                Zone        = $zoneName
                ApprovedBy  = $_.fsi_approvedby
                Justification = $_.fsi_justification
                ExpiresAt   = $_.fsi_expiresat
                IsActive    = $_.fsi_isactive
            }
        }
    } catch {
        Write-Warning "Failed to get action confirmation exceptions: $($_.Exception.Message)"
        return @()
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
        - configuration: JSON blob containing bot configuration
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

function Get-BotActionSettings {
    <#
    .SYNOPSIS
        Queries bot component records for action nodes in topic content.

    .DESCRIPTION
        Queries the botcomponent table filtered by componenttype for action nodes.
        Parses the content JSON to extract action configuration including whether
        user confirmation is configured for each action.

        Bot components with action nodes contain:
        - botcomponentid: Unique identifier
        - name: Component display name
        - componenttype: Type of component (action, trigger, topic, etc.)
        - content: JSON blob containing action configuration
        - _botid_value: Reference to parent bot

    .PARAMETER DataverseUrl
        The Dataverse URL for the environment to query.

    .PARAMETER AccessToken
        Bearer token for Dataverse authentication.

    .PARAMETER BotId
        The bot ID to filter components for a specific agent.

    .OUTPUTS
        Array of PSCustomObject with: ComponentId, Name, BotId, ActionType,
        ActionName, ConnectorId, HasConfirmation, RawContent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataverseUrl,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [string]$BotId
    )

    try {
        $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
        if ($BotId -notmatch $guidPattern) {
            throw "BotId '$BotId' is not a valid GUID format."
        }

        $baseUrl = $DataverseUrl.TrimEnd('/')
        $select = "botcomponentid,name,componenttype,content,_botid_value"
        $filter = "_botid_value eq '$BotId' and statecode eq 0"

        $uri = "$baseUrl/api/data/v9.2/botcomponents?`$select=$select&`$filter=$filter"

        $headers = @{
            'Authorization'    = "Bearer $AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        $allComponents = @()
        $nextLink = $uri

        while ($nextLink) {
            $response = Invoke-DataverseRequest -Uri $nextLink -Method Get -Headers $headers
            $allComponents += $response.value
            $nextLink = $response.'@odata.nextLink'
        }

        Write-Verbose "Retrieved $($allComponents.Count) bot components for bot $BotId"

        # Parse action nodes from component content
        $actionSettings = @()

        foreach ($component in $allComponents) {
            if (-not $component.content) { continue }

            try {
                $content = $component.content | ConvertFrom-Json -ErrorAction Stop

                # Look for action nodes in topic content
                # Bot topics contain action nodes with connector references and confirmation settings
                $actions = @()

                # Check for actions array at top level
                if ($content.PSObject.Properties.Name -contains 'actions') {
                    $actions += @($content.actions)
                }

                # Check for action nodes within topic nodes/steps
                if ($content.PSObject.Properties.Name -contains 'nodes') {
                    foreach ($node in $content.nodes) {
                        if ($node.PSObject.Properties.Name -contains 'type' -and
                            $node.type -in @('Action', 'action', 'InvokeConnectorAction', 'InvokeFlowAction', 'HttpRequestAction')) {
                            $actions += $node
                        }
                    }
                }

                # Check for steps-based format
                if ($content.PSObject.Properties.Name -contains 'steps') {
                    foreach ($step in $content.steps) {
                        if ($step.PSObject.Properties.Name -contains 'kind' -and
                            $step.kind -in @('Action', 'action', 'InvokeConnectorAction', 'InvokeFlowAction', 'HttpRequestAction')) {
                            $actions += $step
                        }
                    }
                }

                foreach ($action in $actions) {
                    # Determine action type
                    $actionType = 'Unknown'
                    $actionTypeProp = $action.PSObject.Properties.Name | Where-Object { $_ -in @('type', 'kind', 'actionType') } | Select-Object -First 1
                    if ($actionTypeProp) {
                        $rawType = $action.$actionTypeProp
                        $typeMap = @{
                            'InvokeConnectorAction' = 'ConnectorAction'
                            'InvokeFlowAction'      = 'CloudFlowAction'
                            'HttpRequestAction'     = 'HttpRequest'
                            'InvokePlugin'          = 'PluginAction'
                            'CustomAction'          = 'CustomAction'
                            'Action'                = 'ConnectorAction'
                        }
                        if ($typeMap.ContainsKey($rawType)) {
                            $actionType = $typeMap[$rawType]
                        }
                    }

                    # Extract action name
                    $actionName = 'Unknown'
                    foreach ($nameKey in @('name', 'displayName', 'actionName', 'operationId')) {
                        if ($action.PSObject.Properties.Name -contains $nameKey -and $action.$nameKey) {
                            $actionName = $action.$nameKey
                            break
                        }
                    }

                    # Extract connector ID
                    $connectorId = $null
                    foreach ($connKey in @('connectorId', 'connectionReference', 'connector')) {
                        if ($action.PSObject.Properties.Name -contains $connKey -and $action.$connKey) {
                            $val = $action.$connKey
                            if ($val -is [string]) {
                                $connectorId = $val
                            } elseif ($val -is [PSCustomObject] -and $val.PSObject.Properties.Name -contains 'id') {
                                $connectorId = $val.id
                            }
                            break
                        }
                    }

                    # Detect confirmation setting
                    $hasConfirmation = $false
                    foreach ($confirmKey in @('requiresConfirmation', 'confirmAction', 'userConfirmation', 'confirmation', 'requireConfirmation')) {
                        if ($action.PSObject.Properties.Name -contains $confirmKey) {
                            $confirmValue = $action.$confirmKey
                            if ($confirmValue -is [bool]) {
                                $hasConfirmation = $confirmValue
                            } elseif ($confirmValue -is [string]) {
                                $hasConfirmation = $confirmValue -in @('true', 'yes', 'enabled')
                            } elseif ($confirmValue -is [PSCustomObject] -and $confirmValue.PSObject.Properties.Name -contains 'enabled') {
                                $hasConfirmation = [bool]$confirmValue.enabled
                            }
                            break
                        }
                    }

                    $actionSettings += [PSCustomObject]@{
                        ComponentId     = $component.botcomponentid
                        ComponentName   = $component.name
                        BotId           = $component._botid_value
                        ActionType      = $actionType
                        ActionName      = $actionName
                        ConnectorId     = $connectorId
                        HasConfirmation = $hasConfirmation
                        RawContent      = ($action | ConvertTo-Json -Depth 5 -Compress)
                    }
                }
            } catch {
                Write-Verbose "Failed to parse component content for '$($component.name)': $($_.Exception.Message)"
            }
        }

        Write-Verbose "Extracted $($actionSettings.Count) action settings from bot $BotId"
        return $actionSettings
    } catch {
        Write-Warning "Failed to query bot action settings for $BotId`: $($_.Exception.Message)"
        return @()
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Invoke-DataverseRequest',
    'Connect-ACADataverse',
    'Get-ACAConnection',
    'Get-ACAEnvironmentVariable',
    'Write-ACAValidationHistory',
    'Write-ACAViolation',
    'Get-ACALastValidation',
    'Get-ActionConfirmationExceptions',
    'Get-AgentBots',
    'Get-BotActionSettings'
)
