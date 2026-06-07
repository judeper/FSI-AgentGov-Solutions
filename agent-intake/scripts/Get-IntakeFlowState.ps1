<#
.SYNOPSIS
    Reports (and optionally repairs) the activation state of the agent-intake cloud flows in a
    Power Platform solution.

.DESCRIPTION
    Functional-verification and recreate-harness helper for the agent-intake lab. Lists every
    cloud flow (workflow category 5) that belongs to the target solution via the
    solutioncomponent table, and reports each flow's statecode (0 = Draft/Off, 1 = Activated)
    and statuscode. This addresses the well-documented "solution import does not activate cloud
    flows" gap: importing a solution leaves flows Off (or Suspended on a connection mismatch),
    so an explicit activation + re-query pass is required before a flow is usable.

    With -Activate, every flow that is not already Activated is PATCHed to statecode = 1 /
    statuscode = 2 and then re-queried to confirm the new state. Because a parent flow that
    calls a child flow can fail to activate before the child is published (the
    ChildFlowNeverPublished trap), -ActivationOrder lets callers activate flows in a known
    dependency order (child flows first) by matching on flow-name substrings.

    With -ExpectedCount, the script exits non-zero unless exactly that many flows are Activated,
    so it can be used as a verification gate in the recreate harness.

    Authentication follows the lab standard: an Azure CLI access token for the target
    environment (az login) or a DATAVERSE_ACCESS_TOKEN environment variable. This helps meet
    the unattended-auth posture used throughout the lab harness.

.PARAMETER EnvironmentUrl
    Dataverse environment URL, for example https://autojude.crm.dynamics.com/.

.PARAMETER SolutionUniqueName
    Unique name of the solution that owns the flows. Defaults to FSIAgentIntake.

.PARAMETER Activate
    Activate every flow that is not already Activated (statecode 1), then re-query to confirm.

.PARAMETER ActivationOrder
    Optional ordered list of flow-name substrings. Flows are activated in this order (child
    flows first) to avoid the ChildFlowNeverPublished activation race. Flows not matched by any
    entry are activated last, in their returned order.

.PARAMETER ExpectedCount
    Optional. When supplied, the script exits non-zero unless exactly this many flows are
    Activated after the run. Use as a verification gate (for example -ExpectedCount 12).

.EXAMPLE
    ./Get-IntakeFlowState.ps1 -EnvironmentUrl https://autojude.crm.dynamics.com/

    Reports the activation state of every cloud flow in the FSIAgentIntake solution.

.EXAMPLE
    ./Get-IntakeFlowState.ps1 -EnvironmentUrl https://autojude.crm.dynamics.com/ -Activate -ActivationOrder 'decision-pack','router' -ExpectedCount 6

    Activates the decision-pack child flow first, then the router, then the rest, and fails
    unless 6 flows end up Activated.

.NOTES
    Cloud flows are workflow rows with category = 5. Solution membership is resolved through the
    solutioncomponent table (componenttype 29 = Workflow). statecode 0 = Draft/Off, 1 = Activated.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SolutionUniqueName = 'FSIAgentIntake',

    [Parameter()]
    [switch]$Activate,

    [Parameter()]
    [string[]]$ActivationOrder,

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$ExpectedCount = -1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CloudFlowCategory = 5
$script:WorkflowComponentType = 29
$script:StateActivated = 1
$script:StateLabels = @{ 0 = 'Draft/Off'; 1 = 'Activated'; 2 = 'Suspended' }

function Get-DataverseAccessToken {
    if (-not [string]::IsNullOrWhiteSpace($env:DATAVERSE_ACCESS_TOKEN)) {
        return $env:DATAVERSE_ACCESS_TOKEN.Trim()
    }
    $az = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -eq $az) {
        throw 'Could not acquire a Dataverse access token. Run az login or set DATAVERSE_ACCESS_TOKEN.'
    }
    $token = & $az.Source account get-access-token --resource $EnvironmentUrl --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Azure CLI token acquisition failed for $EnvironmentUrl. Run az login."
    }
    return $token.Trim()
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'PATCH')][string]$Method,
        [Parameter(Mandatory = $true)][string]$RelativeUri,
        [Parameter()][object]$Body
    )
    $uri = '{0}/api/data/v9.2/{1}' -f $EnvironmentUrl.TrimEnd('/'), $RelativeUri.TrimStart('/')
    $headers = @{
        Authorization      = "Bearer $(Get-DataverseAccessToken)"
        Accept             = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }
    $params = @{ Method = $Method; Uri = $uri; Headers = $headers; TimeoutSec = 60 }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $params['Body'] = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
        $params['ContentType'] = 'application/json; charset=utf-8'
    }
    return Invoke-RestMethod @params
}

function Resolve-SolutionId {
    $filter = "uniquename eq '{0}'" -f $SolutionUniqueName.Replace("'", "''")
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("solutions?`$select=solutionid,uniquename&`$filter={0}" -f $filter)
    if ($null -eq $response.value -or $response.value.Count -eq 0) {
        throw "Solution '$SolutionUniqueName' not found in $EnvironmentUrl."
    }
    return [string]$response.value[0].solutionid
}

function Get-SolutionFlow {
    param([Parameter(Mandatory = $true)][string]$SolutionId)

    $componentFilter = "_solutionid_value eq $SolutionId and componenttype eq $script:WorkflowComponentType"
    $components = Invoke-DataverseRequest -Method GET -RelativeUri ("solutioncomponents?`$select=objectid&`$filter={0}" -f $componentFilter)

    $flows = New-Object System.Collections.Generic.List[object]
    foreach ($component in @($components.value)) {
        $workflowId = [string]$component.objectid
        $select = 'name,category,type,statecode,statuscode,workflowid'
        $flow = Invoke-DataverseRequest -Method GET -RelativeUri ("workflows({0})?`$select={1}" -f $workflowId, $select)
        if ([int]$flow.category -ne $script:CloudFlowCategory) { continue }
        $flows.Add($flow) | Out-Null
    }
    return $flows
}

function Get-OrderedFlow {
    param(
        [Parameter(Mandatory = $true)][object[]]$Flows,
        [Parameter()][string[]]$Order
    )

    if (-not $Order -or $Order.Count -eq 0) { return $Flows }

    $ordered = New-Object System.Collections.Generic.List[object]
    foreach ($token in $Order) {
        foreach ($flow in $Flows) {
            if (($ordered -notcontains $flow) -and ([string]$flow.name -like "*$token*")) {
                $ordered.Add($flow) | Out-Null
            }
        }
    }
    foreach ($flow in $Flows) {
        if ($ordered -notcontains $flow) { $ordered.Add($flow) | Out-Null }
    }
    return $ordered
}

function Format-State {
    param([int]$StateCode)
    if ($script:StateLabels.ContainsKey($StateCode)) { return $script:StateLabels[$StateCode] }
    return "Other($StateCode)"
}

# --- Main ----------------------------------------------------------------------------------
Write-Host "Environment : $EnvironmentUrl" -ForegroundColor Cyan
Write-Host "Solution    : $SolutionUniqueName" -ForegroundColor Cyan

$solutionId = Resolve-SolutionId
$flows = @(Get-SolutionFlow -SolutionId $solutionId)

if ($flows.Count -eq 0) {
    Write-Host "`nNo cloud flows (category 5) found in the solution yet." -ForegroundColor Yellow
}

if ($Activate -and $flows.Count -gt 0) {
    $orderedFlows = @(Get-OrderedFlow -Flows $flows -Order $ActivationOrder)
    foreach ($flow in $orderedFlows) {
        if ([int]$flow.statecode -eq $script:StateActivated) {
            Write-Host ("  = {0} already Activated" -f $flow.name) -ForegroundColor DarkGray
            continue
        }
        if ($PSCmdlet.ShouldProcess([string]$flow.name, 'Activate cloud flow (statecode = 1)')) {
            Invoke-DataverseRequest -Method PATCH -RelativeUri ("workflows({0})" -f $flow.workflowid) `
                -Body @{ statecode = 1; statuscode = 2 } | Out-Null
            Write-Host ("  + Activated {0}" -f $flow.name) -ForegroundColor Green
        }
    }
    # Re-query so the report and the gate reflect the post-activation state.
    $flows = @(Get-SolutionFlow -SolutionId $solutionId)
}

$report = foreach ($flow in $flows) {
    [pscustomobject]@{
        Name      = [string]$flow.name
        State     = Format-State -StateCode ([int]$flow.statecode)
        StateCode = [int]$flow.statecode
        Status    = [int]$flow.statuscode
    }
}

if ($report) {
    Write-Host ""
    $report | Sort-Object Name | Format-Table -AutoSize
}

$activatedCount = @($flows | Where-Object { [int]$_.statecode -eq $script:StateActivated }).Count
$totalCount = $flows.Count
Write-Host ("Activated   : {0} of {1} flow(s)" -f $activatedCount, $totalCount) -ForegroundColor Cyan

if ($ExpectedCount -ge 0) {
    if ($activatedCount -ne $ExpectedCount) {
        Write-Error ("Verification gate FAILED: expected {0} Activated flow(s), found {1}." -f $ExpectedCount, $activatedCount)
        exit 1
    }
    Write-Host ("Verification gate PASSED: {0} Activated flow(s)." -f $ExpectedCount) -ForegroundColor Green
}

return [pscustomobject]@{
    Solution       = $SolutionUniqueName
    TotalFlows     = $totalCount
    ActivatedFlows = $activatedCount
    Flows          = $report
}
