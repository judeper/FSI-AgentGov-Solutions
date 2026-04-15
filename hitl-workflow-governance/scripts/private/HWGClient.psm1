<#
.SYNOPSIS
    HITL Workflow Governance Dataverse client module.

.DESCRIPTION
    Provides helper functions for Dataverse interaction with the HWG solution.
    Follows the proven ACAClient pattern with HWG_ environment variable prefix.

    Tables:
    - fsi_hitlcheckpointresults: Individual HITL checkpoint validation findings per agent/action
    - fsi_hitlscanrun: Immutable audit trail of scan run summaries
    - fsi_hitlcheckpointexceptions: Approved exception records for specific checkpoints

.NOTES
    Module: HWGClient.psm1
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

# HITL checkpoint type picklist mapping
$script:CheckpointTypeToInt = @{
    'RequestForInformation'   = 100000000
    'MultistageApproval'      = 100000001
    'CustomHitl'              = 100000002
}
$script:IntToCheckpointType = @{
    100000000 = 'RequestForInformation'
    100000001 = 'MultistageApproval'
    100000002 = 'CustomHitl'
}

# HITL checkpoint status picklist mapping
$script:CheckpointStatusToInt = @{
    'Present'            = 100000000
    'Missing'            = 100000001
    'Partial'            = 100000002
    'UnableToDetermine'  = 100000003
}
$script:IntToCheckpointStatus = @{
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

# Action category picklist mapping (classifies the action the HITL checkpoint guards)
$script:ActionCategoryToInt = @{
    'Write'              = 100000000
    'Financial'          = 100000001
    'ExternalSharing'    = 100000002
    'PiiProcessing'      = 100000003
    'CustomerFacing'     = 100000004
    'InternalReadOnly'   = 100000005
    'Unknown'            = 100000006
}
$script:IntToActionCategory = @{
    100000000 = 'Write'
    100000001 = 'Financial'
    100000002 = 'ExternalSharing'
    100000003 = 'PiiProcessing'
    100000004 = 'CustomerFacing'
    100000005 = 'InternalReadOnly'
    100000006 = 'Unknown'
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

function Connect-HWGDataverse {
    <#
    .SYNOPSIS
        Establishes connection to Dataverse for HWG operations.

    .DESCRIPTION
        Stores the Dataverse URL and access token for use by other HWG module functions.
        If no access token is provided, attempts to acquire one via Az.Accounts.

    .PARAMETER DataverseUrl
        The Dataverse environment URL (e.g., https://org.crm.dynamics.com).

    .PARAMETER AccessToken
        Optional pre-acquired Bearer access token.

    .EXAMPLE
        Connect-HWGDataverse -DataverseUrl "https://myorg.crm.dynamics.com" -AccessToken $token
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

function Get-HWGConnection {
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

function Get-HWGEnvironmentVariable {
    <#
    .SYNOPSIS
        Retrieves HWG environment variable value from Dataverse.

    .DESCRIPTION
        Queries the environmentvariabledefinitions table for variables with the
        fsi_HWG_ prefix. Returns the current value or default if not set.

    .PARAMETER Name
        Variable name (without fsi_HWG_ prefix).

    .PARAMETER DefaultValue
        Value to return if variable not found.

    .EXAMPLE
        Get-HWGEnvironmentVariable -Name "ScanIntervalHours" -DefaultValue 24
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
        $schemaName = "fsi_HWG_$Name"
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

function Write-HitlScanRun {
    <#
    .SYNOPSIS
        Writes immutable scan run record to Dataverse.

    .DESCRIPTION
        Creates a record in fsi_hitlscanrun capturing scan execution summary metrics.
        This provides an immutable audit trail of all HITL checkpoint validation runs.

    .PARAMETER ValidationResult
        Hashtable containing scan run summary metrics including:
        - TotalAgents: Total agents scanned
        - AgentsWithHitl: Agents that have HITL checkpoints configured
        - AgentsMissingHitl: Agents missing required HITL checkpoints
        - TotalCheckpoints: Total HITL checkpoints discovered
        - OverallStatus: Summary status string
        - EnvironmentsScanned: Count of environments scanned

    .PARAMETER RunId
        GUID correlating all records from a single scan execution.

    .EXAMPLE
        Write-HitlScanRun -ValidationResult $summary -RunId $runGuid
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
        $body = @{
            fsi_name                = "HITL Scan - $($RunId.Substring(0,8))"
            fsi_runid               = $RunId
            fsi_scantime            = (Get-Date).ToUniversalTime().ToString("o")
            fsi_totalagents         = [int]($ValidationResult.TotalAgents ?? 0)
            fsi_totalflows          = [int]($ValidationResult.TotalFlows ?? 0)
            fsi_checkpointsfound    = [int]($ValidationResult.FlowsWithHitl ?? $ValidationResult.CheckpointsFound ?? 0)
            fsi_checkpointsmissing  = [int](($ValidationResult.TotalFlows ?? 0) - ($ValidationResult.FlowsWithHitl ?? $ValidationResult.CheckpointsFound ?? 0))
            fsi_violationcount      = [int]($ValidationResult.ViolationCount ?? 0)
            fsi_overallstatus       = $ValidationResult.OverallStatus
            fsi_summaryjson         = ($ValidationResult | ConvertTo-Json -Depth 5 -Compress)
        }
        if ($null -ne $ValidationResult.CompliantCount) {
            $body['fsi_compliantcount'] = [int]$ValidationResult.CompliantCount
        }
        if ($null -ne $ValidationResult.AgentsWithHitl) {
            $body['fsi_agentswithhitl'] = [int]$ValidationResult.AgentsWithHitl
        }
        if ($null -ne $ValidationResult.AgentsMissingHitl) {
            $body['fsi_agentsmissinghitl'] = [int]$ValidationResult.AgentsMissingHitl
        }
        if ($null -ne $ValidationResult.TotalCheckpoints) {
            $body['fsi_totalcheckpoints'] = [int]$ValidationResult.TotalCheckpoints
        }
        if ($null -ne $ValidationResult.EnvironmentsScanned) {
            $body['fsi_environmentsscanned'] = [int]$ValidationResult.EnvironmentsScanned
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_hitlscanruns"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($body | ConvertTo-Json) -Headers $headers
        Write-Verbose "HWG scan run record created"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write scan run record (audit trail gap): $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Checkpoint Result Functions

function Write-HitlCheckpointResult {
    <#
    .SYNOPSIS
        Writes HITL checkpoint validation result record to Dataverse.

    .DESCRIPTION
        Creates a record in fsi_hitlcheckpointresults capturing the validation
        outcome for a specific agent action's HITL checkpoint configuration.

    .PARAMETER Result
        Hashtable containing checkpoint result details:
        - EnvironmentGuid: Environment GUID
        - EnvironmentName: Display name
        - AgentId: Agent/bot GUID
        - AgentName: Agent display name
        - Zone: Governance zone (Zone1/Zone2/Zone3/Unknown)
        - FlowName: Name of the flow being validated
        - FlowId: Optional flow identifier
        - ActionCategory: Category (Write/Financial/ExternalSharing/PiiProcessing/CustomerFacing/InternalReadOnly)
        - CheckpointType: Type of HITL checkpoint found (or expected)
        - CheckpointStatus: Present/Missing/Partial/UnableToDetermine
        - Severity: Critical/High/Medium/Low/Warning
        - RegulatoryContext: Regulatory citation string
        - HasHitlCheckpoint: Boolean checkpoint indicator
        - ViolationStatus: Open/Acknowledged/Excepted/Resolved

    .PARAMETER RunId
        Optional GUID correlating this result to a scan execution.

    .EXAMPLE
        Write-HitlCheckpointResult -Result $finding -RunId $runGuid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Result,

        [Parameter()]
        [string]$RunId
    )

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected, skipping checkpoint result write"
        return $null
    }

    try {
        # Convert zone string to picklist integer for Dataverse
        $zoneInt = if ($script:ZoneToInt.ContainsKey($Result.Zone)) {
            $script:ZoneToInt[$Result.Zone]
        } else { 0 }

        # Convert checkpoint type string to picklist integer for Dataverse
        $checkpointTypeInt = if ($Result.CheckpointType -and $script:CheckpointTypeToInt.ContainsKey($Result.CheckpointType)) {
            $script:CheckpointTypeToInt[$Result.CheckpointType]
        } else { $null }

        # Convert checkpoint status string to picklist integer for Dataverse
        $checkpointStatusInt = if ($Result.CheckpointStatus -and $script:CheckpointStatusToInt.ContainsKey($Result.CheckpointStatus)) {
            $script:CheckpointStatusToInt[$Result.CheckpointStatus]
        } else { $null }

        # Convert action category string (used locally for policy evaluation, not persisted as a column)

        $hasHitlCheckpoint = if ($null -ne $Result.HasHitlCheckpoint) {
            [bool]$Result.HasHitlCheckpoint
        } else {
            $Result.CheckpointStatus -eq 'Present'
        }
        $violationStatusInt = if ($Result.ViolationStatus -and $script:ViolationStatusToInt.ContainsKey($Result.ViolationStatus)) {
            $script:ViolationStatusToInt[$Result.ViolationStatus]
        } elseif ($hasHitlCheckpoint) {
            $script:ViolationStatusToInt['Resolved']
        } else {
            $script:ViolationStatusToInt['Open']
        }

        $record = @{
            fsi_name              = "$($Result.AgentName)-$($Result.FlowName)-$(Get-Date -Format 'yyyy-MM-dd')"
            fsi_environmentguid   = $Result.EnvironmentGuid
            fsi_environmentname   = $Result.EnvironmentName
            fsi_agentid           = $Result.AgentId
            fsi_agentname         = $Result.AgentName
            fsi_zone              = $zoneInt
            fsi_flowname          = $Result.FlowName
            fsi_severity          = $Result.Severity
            fsi_regulatorycontext = $Result.RegulatoryContext
            fsi_checkpointstatus  = $checkpointStatusInt
            fsi_hashitlcheckpoint = $hasHitlCheckpoint
            fsi_violationstatus   = $violationStatusInt
            fsi_detectedat        = (Get-Date).ToUniversalTime().ToString('o')
        }

        # Add checkpoint type if resolved
        if ($null -ne $checkpointTypeInt) {
            $record['fsi_checkpointtype'] = $checkpointTypeInt
        }

        # Note: ActionCategory is a local classification for policy evaluation, not a Dataverse column

        if ($Result.FlowId) {
            $record['fsi_flowid'] = $Result.FlowId
        }

        if ($RunId) {
            $record['fsi_runid'] = $RunId
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_hitlcheckpointresults"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
        Write-Verbose "HWG checkpoint result record created for $($Result.AgentName) - $($Result.FlowName)"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write checkpoint result record for '$($Result.AgentName)': $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Violation Functions

function Write-HitlViolation {
    <#
    .SYNOPSIS
        Writes HITL policy violation record to Dataverse.

    .DESCRIPTION
        Creates a violation record when an agent is missing a required HITL checkpoint
        or has an improperly configured checkpoint. Violations drive the supervision
        workflow and remediation tracking.

    .PARAMETER Violation
        Hashtable containing violation details:
        - EnvironmentGuid: Environment GUID
        - EnvironmentName: Display name
        - AgentId: Agent/bot GUID
        - AgentName: Agent display name
        - Zone: Governance zone
        - FlowName: Name of the flow missing HITL
        - FlowId: Optional flow identifier
        - Severity: Critical/High/Medium/Low/Warning
        - RegulatoryContext: Regulatory citation string
        - CheckpointType: Optional checkpoint type
        - ViolationType: Violation classification

    .PARAMETER RunId
        Optional GUID correlating this violation to a scan execution.

    .EXAMPLE
        Write-HitlViolation -Violation $finding -RunId $runGuid
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
        # Map zone string to option set value
        $zoneValue = switch ($Violation.Zone) {
            'Zone1' { 100000000 }
            'Zone2' { 100000001 }
            'Zone3' { 100000002 }
            default { 100000002 }
        }

        # Map severity to option set value
        $severityValue = switch ($Violation.Severity) {
            'Critical' { 100000000 }
            'High'     { 100000001 }
            'Medium'   { 100000002 }
            'Low'      { 100000003 }
            'Warning'  { 100000004 }
            default    { 100000002 }
        }

        # Map checkpoint type - default to StepConfirmation if not provided
        $checkpointTypeValue = switch ($Violation.CheckpointType) {
            'StepConfirmation'  { 100000000 }
            'HumanApproval'     { 100000001 }
            'SupervisorReview'  { 100000002 }
            'EscalationTrigger' { 100000003 }
            default             { 100000000 }
        }

        $body = @{
            fsi_name              = "Violation - $($Violation.AgentName ?? $Violation.AgentId) - $($RunId.Substring(0,8))"
            fsi_environmentguid   = $Violation.EnvironmentGuid
            fsi_environmentname   = $Violation.EnvironmentName
            fsi_agentid           = $Violation.AgentId
            fsi_agentname         = $Violation.AgentName
            fsi_zone              = $zoneValue
            fsi_checkpointtype    = $checkpointTypeValue
            fsi_checkpointstatus  = 100000002
            fsi_hashitlcheckpoint = $false
            fsi_violationstatus   = 100000000
            fsi_severity          = $severityValue
            fsi_detectedat        = (Get-Date).ToUniversalTime().ToString("o")
            fsi_runid             = $RunId
        }
        if ($Violation.FlowName) {
            $body['fsi_flowname'] = $Violation.FlowName
        }
        if ($Violation.FlowId) {
            $body['fsi_flowid'] = $Violation.FlowId
        }
        if ($Violation.ViolationType) {
            $body['fsi_violationtype'] = $Violation.ViolationType
        }
        if ($Violation.RegulatoryContext) {
            $body['fsi_regulatorycontext'] = $Violation.RegulatoryContext
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_hitlcheckpointresults"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($body | ConvertTo-Json) -Headers $headers
        Write-Verbose "HWG violation record created for $($Violation.AgentName) - $($Violation.FlowName)"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write violation record for '$($Violation.AgentName)': $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Query Functions

function Get-HWGLastValidation {
    <#
    .SYNOPSIS
        Retrieves recent scan run records from Dataverse.

    .DESCRIPTION
        Queries the fsi_hitlscanrun table ordered by timestamp descending.
        Used to compare current scan results against previous runs.

    .PARAMETER Top
        Number of recent scan runs to retrieve. Default: 1.

    .EXAMPLE
        Get-HWGLastValidation -Top 5
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
        $select = "fsi_name,fsi_runid,fsi_overallstatus,fsi_totalagents,fsi_agentswithhitl,fsi_agentsmissinghitl,fsi_totalcheckpoints,fsi_summaryjson,fsi_scantime"
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_hitlscanruns?" +
               "`$orderby=fsi_scantime desc&`$top=$Top&`$select=$select"

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
                    Name                 = $_.fsi_name
                    RunId                = $_.fsi_runid
                    OverallStatus        = $_.fsi_overallstatus
                    TotalAgents          = $_.fsi_totalagents
                    AgentsWithHitl       = $_.fsi_agentswithhitl
                    AgentsMissingHitl    = $_.fsi_agentsmissinghitl
                    TotalCheckpoints     = $_.fsi_totalcheckpoints
                    SummaryJson          = $_.fsi_summaryjson
                    Timestamp            = $_.fsi_scantime
                }
            }
        }

        return $null
    } catch {
        Write-Warning "Failed to get scan run history: $($_.Exception.Message)"
        return $null
    }
}

function Get-HitlCheckpointExceptions {
    <#
    .SYNOPSIS
        Queries approved HITL checkpoint exceptions from Dataverse.

    .DESCRIPTION
        Returns records from the fsi_hitlcheckpointexceptions table. These represent
        approved exceptions where specific agent actions are permitted to operate
        without HITL checkpoints, optionally filtered by zone and agent.

    .PARAMETER Zone
        Optional zone filter (Zone1, Zone2, Zone3).

    .PARAMETER AgentId
        Optional agent ID to filter exceptions for a specific agent.

    .PARAMETER ActiveOnly
        When specified, returns only active (non-expired) exceptions.

    .OUTPUTS
        Array of PSCustomObject with: ExceptionId, ActionName, ActionCategory,
        AgentId, AgentName, Zone, ApprovedBy, Reason, ExpiresAt, IsActive

    .EXAMPLE
        Get-HitlCheckpointExceptions -Zone Zone3 -ActiveOnly
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

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_hitlcheckpointexceptions?" +
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

            # Convert action category integer back to string
            $actionCatValue = $_.fsi_actioncategory
            $actionCatName = if ($null -ne $actionCatValue -and $script:IntToActionCategory.ContainsKey([int]$actionCatValue)) {
                $script:IntToActionCategory[[int]$actionCatValue]
            } else { 'Unknown' }

            [PSCustomObject]@{
                ExceptionId    = $_.fsi_hitlcheckpointexceptionid
                ActionName     = $_.fsi_actionname
                ActionCategory = $actionCatName
                AgentId        = $_.fsi_agentid
                AgentName      = $_.fsi_agentname
                Zone           = $zoneName
                ApprovedBy     = $_.fsi_approvedby
                Reason         = $_.fsi_reason
                ExpiresAt      = $_.fsi_expiresat
                IsActive       = $_.fsi_isactive
            }
        }
    } catch {
        Write-Warning "Failed to get HITL checkpoint exceptions: $($_.Exception.Message)"
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

    .PARAMETER DataverseUrl
        The Dataverse URL for the environment to query.

    .PARAMETER AccessToken
        Bearer token for Dataverse authentication.

    .PARAMETER IncludeDrafts
        When specified, includes inactive/draft bots (statecode != 0).

    .EXAMPLE
        Get-AgentBots -DataverseUrl $url -AccessToken $token
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

function Get-BotHitlSettings {
    <#
    .SYNOPSIS
        Queries bot component records for HITL checkpoint nodes in topic content.

    .DESCRIPTION
        Queries the botcomponent table and parses topic content JSON to extract
        HITL checkpoint configuration — specifically looking for "Request for Information"
        and "Run a Multistage Approval" connector actions from the Human in the Loop
        connector.

    .PARAMETER DataverseUrl
        The Dataverse URL for the environment to query.

    .PARAMETER AccessToken
        Bearer token for Dataverse authentication.

    .PARAMETER BotId
        The bot ID to filter components for a specific agent.

    .OUTPUTS
        Array of PSCustomObject with: ComponentId, ComponentName, BotId,
        ActionName, CheckpointType, HasHitlCheckpoint, ActionCategory, RawContent

    .EXAMPLE
        Get-BotHitlSettings -DataverseUrl $url -AccessToken $token -BotId $botId
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
        $select = "botcomponentid,name,componenttype,content,_parentbotid_value"
        $filter = "_parentbotid_value eq '$BotId' and statecode eq 0"

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

        # HITL connector action identifiers
        $hitlConnectorIds = @(
            'shared_teams',
            'shared_approvals',
            'shared_office365',
            'shared_microsoftcopilotforstudio'
        )
        $hitlActionNames = @(
            'RequestForInformation',
            'RunMultistageApproval',
            'Request for Information',
            'Run a Multistage Approval',
            'requestforinformation',
            'runmultistageapproval'
        )

        $hitlSettings = @()

        foreach ($component in $allComponents) {
            if (-not $component.content) { continue }

            try {
                $content = $component.content | ConvertFrom-Json -ErrorAction Stop

                $actions = @()

                # Check for actions array at top level
                if ($content.PSObject.Properties.Name -contains 'actions') {
                    $actions += @($content.actions)
                }

                # Check for action nodes within topic nodes
                if ($content.PSObject.Properties.Name -contains 'nodes') {
                    foreach ($node in $content.nodes) {
                        if ($node.PSObject.Properties.Name -contains 'type' -and
                            $node.type -in @('Action', 'action', 'InvokeConnectorAction', 'InvokeFlowAction')) {
                            $actions += $node
                        }
                    }
                }

                # Check for steps-based format
                if ($content.PSObject.Properties.Name -contains 'steps') {
                    foreach ($step in $content.steps) {
                        if ($step.PSObject.Properties.Name -contains 'kind' -and
                            $step.kind -in @('Action', 'action', 'InvokeConnectorAction', 'InvokeFlowAction')) {
                            $actions += $step
                        }
                    }
                }

                foreach ($action in $actions) {
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

                    # Detect HITL checkpoint presence
                    $isHitlCheckpoint = $false
                    $checkpointType = $null

                    # Match by action name
                    $normalizedActionName = $actionName.Trim().ToLower() -replace '\s+', ''
                    if ($normalizedActionName -in @('requestforinformation', 'runmultistageapproval',
                        'request for information', 'run a multistage approval')) {
                        $isHitlCheckpoint = $true
                        $checkpointType = if ($normalizedActionName -match 'approval') {
                            'MultistageApproval'
                        } else {
                            'RequestForInformation'
                        }
                    }

                    # Match by connector ID
                    if (-not $isHitlCheckpoint -and $connectorId) {
                        $normalizedConnector = $connectorId.Trim().ToLower()
                        if ($normalizedConnector -in $hitlConnectorIds -and
                            $actionName -in $hitlActionNames) {
                            $isHitlCheckpoint = $true
                        }
                    }

                    # Classify action category
                    $actionCategory = Get-ActionCategory -ActionName $actionName -ConnectorId $connectorId

                    $hitlSettings += [PSCustomObject]@{
                        ComponentId       = $component.botcomponentid
                        ComponentName     = $component.name
                        BotId             = $component._parentbotid_value
                        ActionName        = $actionName
                        CheckpointType    = $checkpointType
                        HasHitlCheckpoint = $isHitlCheckpoint
                        ActionCategory    = $actionCategory
                        ConnectorId       = $connectorId
                        RawContent        = ($action | ConvertTo-Json -Depth 5 -Compress)
                    }
                }
            } catch {
                Write-Verbose "Failed to parse component content for '$($component.name)': $($_.Exception.Message)"
            }
        }

        Write-Verbose "Extracted $($hitlSettings.Count) action settings from bot $BotId"
        return $hitlSettings
    } catch {
        Write-Warning "Failed to query bot HITL settings for $BotId`: $($_.Exception.Message)"
        return @()
    }
}

#endregion

#region Helper Functions

function Get-ActionCategory {
    <#
    .SYNOPSIS
        Classifies an action into a governance category based on name and connector.
    #>
    [CmdletBinding()]
    param(
        [string]$ActionName,
        [string]$ConnectorId
    )

    if ([string]::IsNullOrWhiteSpace($ActionName)) {
        return 'Unknown'
    }

    $normalized = $ActionName.Trim().ToLower()

    # Financial action patterns
    if ($normalized -match 'payment|transfer|transaction|invoice|billing|refund|charge|deposit|withdraw') {
        return 'Financial'
    }

    # External sharing patterns
    if ($normalized -match 'share|external|export|send.*email|send.*message|publish|distribute') {
        return 'ExternalSharing'
    }

    # PII processing patterns
    if ($normalized -match 'pii|personal|ssn|social.security|customer.data|kyc|identity|passport') {
        return 'PiiProcessing'
    }

    # Customer-facing patterns
    if ($normalized -match 'customer|client|consumer|user.*facing|public.*api|chat.*response') {
        return 'CustomerFacing'
    }

    # Write action patterns
    if ($normalized -match 'create|update|delete|modify|write|patch|put|insert|remove|upsert') {
        return 'Write'
    }

    # Read-only patterns
    if ($normalized -match 'get|read|list|query|fetch|search|lookup|retrieve') {
        return 'InternalReadOnly'
    }

    # Connector-based classification
    if ($ConnectorId) {
        $normalizedConnector = $ConnectorId.Trim().ToLower()
        if ($normalizedConnector -match 'sharepoint|onedrive|outlook|exchange') {
            return 'ExternalSharing'
        }
        if ($normalizedConnector -match 'dataverse|sql|cosmos') {
            return 'Write'
        }
    }

    return 'Unknown'
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Invoke-DataverseRequest',
    'Connect-HWGDataverse',
    'Get-HWGConnection',
    'Get-HWGEnvironmentVariable',
    'Write-HitlScanRun',
    'Write-HitlCheckpointResult',
    'Write-HitlViolation',
    'Get-HWGLastValidation',
    'Get-HitlCheckpointExceptions',
    'Get-AgentBots',
    'Get-BotHitlSettings',
    'Get-ActionCategory'
)
