<#
.SYNOPSIS
    Queries existing HITL checkpoint validation results from Dataverse.

.DESCRIPTION
    Retrieves records from the fsi_hitlcheckpointresults and fsi_hitlscanrun tables
    with optional filtering by RunId, Zone, and Severity. Returns typed PSCustomObject
    arrays for pipeline consumption.

.PARAMETER DataverseUrl
    The Dataverse environment URL (e.g., https://org.crm.dynamics.com).

.PARAMETER AccessToken
    Bearer access token for Dataverse authentication.

.PARAMETER RunId
    Optional scan run GUID to filter results for a specific execution.

.PARAMETER Zone
    Optional governance zone filter (Zone1, Zone2, Zone3, Unknown).

.PARAMETER Severity
    Optional severity filter (Critical, High, Medium, Low, Warning).

.PARAMETER Top
    Maximum number of results to return. Default: 500.

.PARAMETER IncludeScanRuns
    When specified, also returns scan run summary records.

.OUTPUTS
    PSCustomObject with CheckpointResults (array) and optionally ScanRuns (array).

.EXAMPLE
    $results = & .\Get-HWGValidationResults.ps1 -DataverseUrl $url -AccessToken $token -Zone Zone3

.EXAMPLE
    $results = & .\Get-HWGValidationResults.ps1 -DataverseUrl $url -AccessToken $token -RunId $guid -IncludeScanRuns

.NOTES
    File: Get-HWGValidationResults.ps1
    Version: 1.0.0
    Requires: PowerShell 7.0+
#>

#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://.*\.crm.*\.dynamics\.com/?$')]
    [string]$DataverseUrl,

    [Parameter(Mandatory)]
    [string]$AccessToken,

    [Parameter()]
    [string]$RunId,

    [Parameter()]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone,

    [Parameter()]
    [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Warning')]
    [string]$Severity,

    [Parameter()]
    [ValidateRange(1, 5000)]
    [int]$Top = 500,

    [Parameter()]
    [switch]$IncludeScanRuns
)

# Zone string-to-integer mapping (must match HWGClient.psm1)
$zoneToInt = @{
    'Unknown' = 0
    'Zone1'   = 1
    'Zone2'   = 2
    'Zone3'   = 3
}
$intToZone = @{
    0 = 'Unknown'
    1 = 'Zone1'
    2 = 'Zone2'
    3 = 'Zone3'
}

$intToCheckpointStatus = @{
    100000000 = 'Present'
    100000001 = 'Missing'
    100000002 = 'Partial'
    100000003 = 'UnableToDetermine'
}

$intToCheckpointType = @{
    100000000 = 'RequestForInformation'
    100000001 = 'MultistageApproval'
    100000002 = 'CustomHitl'
    100000003 = 'AdvancedApprovalsGeneric'
    100000004 = 'NotApplicable'
}

$baseUrl = $DataverseUrl.TrimEnd('/')

$headers = @{
    'Authorization'    = "Bearer $AccessToken"
    'Accept'           = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
}

#region Query Checkpoint Results

$filters = @()

if ($RunId) {
    $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    if ($RunId -notmatch $guidPattern) {
        throw "RunId '$RunId' is not a valid GUID format."
    }
    $filters += "fsi_runid eq '$RunId'"
}

if ($Zone) {
    $zoneInt = $zoneToInt[$Zone]
    $filters += "fsi_zone eq $zoneInt"
}

if ($Severity) {
    $filters += "fsi_severity eq '$Severity'"
}

$filterString = if ($filters.Count -gt 0) {
    "&`$filter=" + ($filters -join ' and ')
} else { '' }

$select = "fsi_name,fsi_runid,fsi_environmentguid,fsi_environmentname,fsi_agentid,fsi_agentname," +
          "fsi_zone,fsi_checkpointtype,fsi_checkpointstatus," +
          "fsi_severity,fsi_regulatorycontext,fsi_flowname,fsi_flowid,fsi_detectedat"

$uri = "$baseUrl/api/data/v9.2/fsi_hitlcheckpointresults?" +
       "`$select=$select&`$orderby=fsi_detectedat desc&`$top=$Top$filterString"

$checkpointResults = @()

try {
    $nextLink = $uri

    while ($nextLink) {
        $response = Invoke-RestMethod -Uri $nextLink -Method Get -Headers $headers -ErrorAction Stop
        $checkpointResults += $response.value
        $nextLink = $response.'@odata.nextLink'

        # Safety: stop paging if we exceed Top
        if ($checkpointResults.Count -ge $Top) { break }
    }

    Write-Verbose "Retrieved $($checkpointResults.Count) checkpoint result records"
} catch {
    Write-Error "Failed to query checkpoint results: $($_.Exception.Message)"
    throw
}

# Transform to typed PSCustomObjects
$typedResults = $checkpointResults | ForEach-Object {
    $zoneValue = $_.fsi_zone
    $zoneName = if ($null -ne $zoneValue -and $intToZone.ContainsKey([int]$zoneValue)) {
        $intToZone[[int]$zoneValue]
    } else { 'Unknown' }

    $checkpointStatusValue = $_.fsi_checkpointstatus
    $checkpointStatusName = if ($null -ne $checkpointStatusValue -and $intToCheckpointStatus.ContainsKey([int]$checkpointStatusValue)) {
        $intToCheckpointStatus[[int]$checkpointStatusValue]
    } else { 'UnableToDetermine' }

    $checkpointTypeValue = $_.fsi_checkpointtype
    $checkpointTypeName = if ($null -ne $checkpointTypeValue -and $intToCheckpointType.ContainsKey([int]$checkpointTypeValue)) {
        $intToCheckpointType[[int]$checkpointTypeValue]
    } else { $null }

    [PSCustomObject]@{
        Name                   = $_.fsi_name
        RunId                  = $_.fsi_runid
        EnvironmentId          = $_.fsi_environmentguid
        EnvironmentDisplayName = $_.fsi_environmentname
        AgentId                = $_.fsi_agentid
        AgentName              = $_.fsi_agentname
        Zone                   = $zoneName
        CheckpointType         = $checkpointTypeName
        CheckpointStatus       = $checkpointStatusName
        Severity               = $_.fsi_severity
        RegulatoryContext      = $_.fsi_regulatorycontext
        FlowName               = $_.fsi_flowname
        FlowId                 = $_.fsi_flowid
        DetectedAt             = $_.fsi_detectedat
    }
}

#endregion

#region Query Scan Runs (optional)

$scanRuns = @()

if ($IncludeScanRuns) {
    $scanSelect = "fsi_name,fsi_runid,fsi_overallstatus,fsi_totalagents,fsi_agentswithhitl," +
                  "fsi_agentsmissinghitl,fsi_totalcheckpoints,fsi_environmentsscanned,fsi_summaryjson,fsi_scantime"

    $scanFilter = if ($RunId) {
        "&`$filter=fsi_runid eq '$RunId'"
    } else { '' }

    $scanUri = "$baseUrl/api/data/v9.2/fsi_hitlscanruns?" +
               "`$select=$scanSelect&`$orderby=fsi_scantime desc&`$top=10$scanFilter"

    try {
        $scanResponse = Invoke-RestMethod -Uri $scanUri -Method Get -Headers $headers -ErrorAction Stop

        $scanRuns = $scanResponse.value | ForEach-Object {
            [PSCustomObject]@{
                Name                 = $_.fsi_name
                RunId                = $_.fsi_runid
                OverallStatus        = $_.fsi_overallstatus
                TotalAgents          = $_.fsi_totalagents
                AgentsWithHitl       = $_.fsi_agentswithhitl
                AgentsMissingHitl    = $_.fsi_agentsmissinghitl
                TotalCheckpoints     = $_.fsi_totalcheckpoints
                EnvironmentsScanned  = $_.fsi_environmentsscanned
                SummaryJson          = $_.fsi_summaryjson
                Timestamp            = $_.fsi_scantime
            }
        }

        Write-Verbose "Retrieved $($scanRuns.Count) scan run records"
    } catch {
        Write-Warning "Failed to query scan runs: $($_.Exception.Message)"
    }
}

#endregion

# Return combined output
[PSCustomObject]@{
    CheckpointResults = $typedResults
    ScanRuns          = $scanRuns
    TotalResults      = $typedResults.Count
    QueryFilters      = [PSCustomObject]@{
        RunId    = $RunId
        Zone     = $Zone
        Severity = $Severity
        Top      = $Top
    }
}
