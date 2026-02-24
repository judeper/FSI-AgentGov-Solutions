<#
.SYNOPSIS
    Agent Communication Restriction Detector Dataverse client module.

.DESCRIPTION
    Provides helper functions for Dataverse interaction with the ACRD solution.
    Follows the proven GACClient pattern with ACRD_ environment variable prefix.

    Tables:
    - fsi_agentcommviolations: Agent-to-agent communication policy violations
    - fsi_approvedcommroutes: Approved zone-to-zone communication routes
    - fsi_agentskillregistrations: Agent skill registration snapshots
    - fsi_commexceptions: Temporary communication route exceptions
    - fsi_commscanrun: Immutable audit trail of communication scan runs

.NOTES
    Module: ACRDClient.psm1
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

# Violation type picklist mapping
$script:ViolationTypeToInt = @{
    'ZONE_BOUNDARY_VIOLATION'       = 100000000
    'CROSS_TENANT_VIOLATION'        = 100000001
    'CROSS_ENVIRONMENT_UNAPPROVED'  = 100000002
    'MAKER_CHECKER_VIOLATION'       = 100000003
}
$script:IntToViolationType = @{
    100000000 = 'ZONE_BOUNDARY_VIOLATION'
    100000001 = 'CROSS_TENANT_VIOLATION'
    100000002 = 'CROSS_ENVIRONMENT_UNAPPROVED'
    100000003 = 'MAKER_CHECKER_VIOLATION'
}

# Violation status picklist mapping
$script:ViolationStatusToInt = @{
    'Open'         = 100000000
    'Acknowledged' = 100000001
    'Remediated'   = 100000002
    'Excepted'     = 100000003
}
$script:IntToViolationStatus = @{
    100000000 = 'Open'
    100000001 = 'Acknowledged'
    100000002 = 'Remediated'
    100000003 = 'Excepted'
}

# Direction type picklist mapping
$script:DirectionTypeToInt = @{
    'OneWay'        = 100000000
    'Bidirectional' = 100000001
}
$script:IntToDirectionType = @{
    100000000 = 'OneWay'
    100000001 = 'Bidirectional'
}

# Exception status picklist mapping
$script:ExceptionStatusToInt = @{
    'Pending'  = 100000000
    'Approved' = 100000001
    'Denied'   = 100000002
    'Expired'  = 100000003
}
$script:IntToExceptionStatus = @{
    100000000 = 'Pending'
    100000001 = 'Approved'
    100000002 = 'Denied'
    100000003 = 'Expired'
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

function Connect-ACRDDataverse {
    <#
    .SYNOPSIS
        Establishes connection to Dataverse for ACRD operations.
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

function Get-ACRDConnection {
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

function Get-ACRDEnvironmentVariable {
    <#
    .SYNOPSIS
        Retrieves ACRD environment variable value from Dataverse.

    .PARAMETER Name
        Variable name (without fsi_ACRD_ prefix).

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
        $schemaName = "fsi_ACRD_$Name"
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

#region Skill Registration Functions

function Get-ACRDSkillRegistration {
    <#
    .SYNOPSIS
        Retrieves agent skill registration records from Dataverse.

    .PARAMETER EnvironmentId
        Optional environment GUID to filter by.

    .PARAMETER AgentId
        Optional agent ID to filter by.

    .PARAMETER ActiveOnly
        When specified, returns only active registrations.
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

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_agentskillregistrations?" +
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

        return $allRecords | ForEach-Object {
            # Convert picklist integers back to zone strings
            $sourceZoneValue = $_.fsi_sourcezone
            $sourceZoneName = if ($null -ne $sourceZoneValue -and $script:IntToZone.ContainsKey([int]$sourceZoneValue)) {
                $script:IntToZone[[int]$sourceZoneValue]
            } else { 'Unknown' }

            $targetZoneValue = $_.fsi_targetzone
            $targetZoneName = if ($null -ne $targetZoneValue -and $script:IntToZone.ContainsKey([int]$targetZoneValue)) {
                $script:IntToZone[[int]$targetZoneValue]
            } else { 'Unknown' }

            [PSCustomObject]@{
                RegistrationId        = $_.fsi_agentskillregistrationid
                Name                  = $_.fsi_name
                EnvironmentGuid       = $_.fsi_environmentguid
                EnvironmentName       = $_.fsi_environmentname
                SourceZone            = $sourceZoneName
                AgentId               = $_.fsi_agentid
                AgentName             = $_.fsi_agentname
                SkillName             = $_.fsi_skillname
                TargetAgentId         = $_.fsi_targetagentid
                TargetAgentName       = $_.fsi_targetagentname
                TargetEnvironmentId   = $_.fsi_targetenvironmentid
                TargetZone            = $targetZoneName
                ManifestUrl           = $_.fsi_manifesturl
                OwnerId               = $_.fsi_ownerid
                IsActive              = $_.fsi_isactive
                CapturedAt            = $_.fsi_capturedat
            }
        }
    } catch {
        Write-Warning "Failed to get skill registrations: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Scan Run Functions

function Write-ACRDScanRun {
    <#
    .SYNOPSIS
        Writes immutable communication scan run record to Dataverse.

    .PARAMETER ScanResult
        Hashtable containing scan summary metrics.

    .PARAMETER RunId
        GUID correlating all records from a single scan execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ScanResult,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected, skipping scan run write"
        return $null
    }

    try {
        $record = @{
            fsi_name                 = "$($ScanResult.OverallStatus)-$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
            fsi_runid                = $RunId
            fsi_scantime             = (Get-Date).ToUniversalTime().ToString('o')
            fsi_totalagents          = $ScanResult.TotalAgents
            fsi_totalskills          = $ScanResult.TotalSkills
            fsi_compliantcount       = $ScanResult.CompliantCount
            fsi_violationcount       = $ScanResult.ViolationCount
            fsi_overallstatus        = $ScanResult.OverallStatus
            fsi_environmentsscanned  = $ScanResult.EnvironmentsScanned
            fsi_summaryjson          = ($ScanResult | ConvertTo-Json -Depth 10 -Compress)
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_commscanruns"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
        Write-Verbose "ACRD scan run record created"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write scan run (audit trail gap): $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Violation Functions

function Write-ACRDViolation {
    <#
    .SYNOPSIS
        Writes agent communication violation record to Dataverse.

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
        # Convert zone strings to picklist integers for Dataverse
        $sourceZoneInt = if ($script:ZoneToInt.ContainsKey($Violation.SourceZone)) {
            $script:ZoneToInt[$Violation.SourceZone]
        } else { 0 }

        $targetZoneInt = if ($script:ZoneToInt.ContainsKey($Violation.TargetZone)) {
            $script:ZoneToInt[$Violation.TargetZone]
        } else { 0 }

        # Convert violation type string to picklist integer
        $violationTypeInt = if ($Violation.ViolationType -and $script:ViolationTypeToInt.ContainsKey($Violation.ViolationType)) {
            $script:ViolationTypeToInt[$Violation.ViolationType]
        } else { $null }

        # Convert violation status string to picklist integer
        $violationStatusInt = if ($Violation.ViolationStatus -and $script:ViolationStatusToInt.ContainsKey($Violation.ViolationStatus)) {
            $script:ViolationStatusToInt[$Violation.ViolationStatus]
        } else { $script:ViolationStatusToInt['Open'] }

        $record = @{
            fsi_name                  = "$($Violation.CallingAgentName)->$($Violation.TargetAgentName)-$(Get-Date -Format 'yyyy-MM-dd')"
            fsi_environmentguid       = $Violation.EnvironmentId
            fsi_environmentname       = $Violation.EnvironmentDisplayName
            fsi_callingagentid        = $Violation.CallingAgentId
            fsi_callingagentname      = $Violation.CallingAgentName
            fsi_targetagentid         = $Violation.TargetAgentId
            fsi_targetagentname       = $Violation.TargetAgentName
            fsi_sourcezone            = $sourceZoneInt
            fsi_targetzone            = $targetZoneInt
            fsi_violationstatus       = $violationStatusInt
            fsi_severity              = $Violation.Severity
            fsi_regulatorycontext     = $Violation.RegulatoryContext
            fsi_detectedat            = (Get-Date).ToUniversalTime().ToString('o')
        }

        # Add violation type if resolved
        if ($null -ne $violationTypeInt) {
            $record['fsi_violationtype'] = $violationTypeInt
        }

        # Add optional fields
        if ($Violation.SkillName) {
            $record['fsi_skillname'] = $Violation.SkillName
        }
        if ($Violation.TargetEnvironmentId) {
            $record['fsi_targetenvironmentid'] = $Violation.TargetEnvironmentId
        }

        if ($RunId) {
            $record['fsi_runid'] = $RunId
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_agentcommviolations"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
        Write-Verbose "ACRD violation record created for $($Violation.CallingAgentName) -> $($Violation.TargetAgentName)"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write violation record for '$($Violation.CallingAgentName)': $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Approved Routes Functions

function Get-ApprovedCommRoutes {
    <#
    .SYNOPSIS
        Queries approved zone-to-zone communication routes from Dataverse.

    .DESCRIPTION
        Returns records from the fsi_approvedcommroutes table. These represent
        the approved communication routes between governance zones that agents
        are permitted to use, optionally filtered by zone and active status.

    .PARAMETER Zone
        Optional source zone filter (Zone1, Zone2, Zone3).

    .PARAMETER ActiveOnly
        When specified, returns only active (non-expired) routes.

    .OUTPUTS
        Array of PSCustomObject with: RouteId, SourceZone, TargetZone,
        DirectionType, AllowCrossEnvironment, ApprovedBy, ExpiresAt, IsActive, Notes
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
            $filter += " and fsi_sourcezone eq $zoneInt"
        }
        if ($ActiveOnly) {
            $filter += " and fsi_isactive eq true"
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_approvedcommroutes?" +
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
            # Convert zone integers back to strings
            $sourceZoneValue = $_.fsi_sourcezone
            $sourceZoneName = if ($null -ne $sourceZoneValue -and $script:IntToZone.ContainsKey([int]$sourceZoneValue)) {
                $script:IntToZone[[int]$sourceZoneValue]
            } else { 'Unknown' }

            $targetZoneValue = $_.fsi_targetzone
            $targetZoneName = if ($null -ne $targetZoneValue -and $script:IntToZone.ContainsKey([int]$targetZoneValue)) {
                $script:IntToZone[[int]$targetZoneValue]
            } else { 'Unknown' }

            # Convert direction type integer back to string
            $directionValue = $_.fsi_directiontype
            $directionName = if ($null -ne $directionValue -and $script:IntToDirectionType.ContainsKey([int]$directionValue)) {
                $script:IntToDirectionType[[int]$directionValue]
            } else { 'OneWay' }

            [PSCustomObject]@{
                RouteId               = $_.fsi_approvedcommrouteid
                SourceZone            = $sourceZoneName
                TargetZone            = $targetZoneName
                DirectionType         = $directionName
                AllowCrossEnvironment = $_.fsi_allowcrossenvironment
                ApprovedBy            = $_.fsi_approvedby
                ExpiresAt             = $_.fsi_expiresat
                IsActive              = $_.fsi_isactive
                Notes                 = $_.fsi_notes
            }
        }
    } catch {
        Write-Warning "Failed to get approved communication routes: $($_.Exception.Message)"
        return @()
    }
}

#endregion

#region Exception Functions

function Get-CommExceptions {
    <#
    .SYNOPSIS
        Queries active communication exceptions from Dataverse.

    .DESCRIPTION
        Returns records from the fsi_commexceptions table. These represent
        temporary exceptions to communication policies, filtered to only
        active (approved, non-expired) exceptions.

    .PARAMETER ActiveOnly
        When specified, returns only approved and non-expired exceptions.

    .OUTPUTS
        Array of PSCustomObject with: ExceptionId, CallingAgentId,
        TargetAgentId, SourceZone, TargetZone, Status, ApprovedBy,
        ExpiresAt, Justification
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$ActiveOnly
    )

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected"
        return @()
    }

    try {
        $filter = "statecode eq 0"
        if ($ActiveOnly) {
            $statusApproved = $script:ExceptionStatusToInt['Approved']
            $filter += " and fsi_exceptionstatus eq $statusApproved"
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_commexceptions?" +
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
            # Convert zone integers back to strings
            $sourceZoneValue = $_.fsi_sourcezone
            $sourceZoneName = if ($null -ne $sourceZoneValue -and $script:IntToZone.ContainsKey([int]$sourceZoneValue)) {
                $script:IntToZone[[int]$sourceZoneValue]
            } else { 'Unknown' }

            $targetZoneValue = $_.fsi_targetzone
            $targetZoneName = if ($null -ne $targetZoneValue -and $script:IntToZone.ContainsKey([int]$targetZoneValue)) {
                $script:IntToZone[[int]$targetZoneValue]
            } else { 'Unknown' }

            # Convert exception status integer back to string
            $statusValue = $_.fsi_exceptionstatus
            $statusName = if ($null -ne $statusValue -and $script:IntToExceptionStatus.ContainsKey([int]$statusValue)) {
                $script:IntToExceptionStatus[[int]$statusValue]
            } else { 'Pending' }

            [PSCustomObject]@{
                ExceptionId     = $_.fsi_commexceptionid
                CallingAgentId  = $_.fsi_callingagentid
                TargetAgentId   = $_.fsi_targetagentid
                SourceZone      = $sourceZoneName
                TargetZone      = $targetZoneName
                Status          = $statusName
                ApprovedBy      = $_.fsi_approvedby
                ExpiresAt       = $_.fsi_expiresat
                Justification   = $_.fsi_justification
            }
        }
    } catch {
        Write-Warning "Failed to get communication exceptions: $($_.Exception.Message)"
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

#endregion

#region Scan History Functions

function Get-ACRDLastScan {
    <#
    .SYNOPSIS
        Retrieves recent scan run records from Dataverse.

    .DESCRIPTION
        Queries the fsi_commscanruns table ordered by timestamp descending.
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
        $select = "fsi_name,fsi_runid,fsi_overallstatus,fsi_violationcount,fsi_totalagents,fsi_totalskills,fsi_summaryjson,fsi_scantime"
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_commscanruns?" +
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
                    Name           = $_.fsi_name
                    RunId          = $_.fsi_runid
                    OverallStatus  = $_.fsi_overallstatus
                    ViolationCount = $_.fsi_violationcount
                    TotalAgents    = $_.fsi_totalagents
                    TotalSkills    = $_.fsi_totalskills
                    SummaryJson    = $_.fsi_summaryjson
                    Timestamp      = $_.fsi_scantime
                }
            }
        }

        return $null
    } catch {
        Write-Warning "Failed to get scan history: $($_.Exception.Message)"
        return $null
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Invoke-DataverseRequest',
    'Connect-ACRDDataverse',
    'Get-ACRDConnection',
    'Get-ACRDEnvironmentVariable',
    'Get-ACRDSkillRegistration',
    'Write-ACRDScanRun',
    'Write-ACRDViolation',
    'Get-ApprovedCommRoutes',
    'Get-CommExceptions',
    'Get-AgentBots',
    'Get-ACRDLastScan'
)
