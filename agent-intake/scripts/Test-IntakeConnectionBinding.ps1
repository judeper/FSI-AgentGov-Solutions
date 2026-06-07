<#
.SYNOPSIS
    Reports (and optionally gates on) the bound/unbound state of the agent-intake connection
    references in a Power Platform solution environment.

.DESCRIPTION
    Functional-verification helper for the agent-intake lab. Reads the connectionreference rows
    whose logical names start with fsi_cr_ and reports, for each, whether it is bound to a
    connection (the connectionid attribute is populated) or still unbound. A flow cannot run
    against an unbound connection reference, so this check is both an FV1 gate (after the
    operator creates and binds connections in the maker portal) and a preflight for the FV3
    recreate harness (before a solution import or an explicit activation pass).

    With -RequireBound, the script exits non-zero unless every listed connection reference is
    bound. The default required set is the three "easy" connection references used by the
    vertical-slice flows (Dataverse, Teams, Office 365); the HTTP-with-Entra and Graph custom
    connector references are not required until the handoff flows are built.

    Authentication follows the lab standard: an Azure CLI access token for the target
    environment (az login) or a DATAVERSE_ACCESS_TOKEN environment variable. This helps meet
    the unattended-auth posture used throughout the lab harness.

.PARAMETER EnvironmentUrl
    Dataverse environment URL, for example https://autojude.crm.dynamics.com/.

.PARAMETER RequireBound
    Connection-reference logical names that must be bound for the run to pass. When any listed
    reference is unbound the script exits 1. Defaults to the three vertical-slice references:
    fsi_cr_dataverse_agentintake, fsi_cr_teams_agentintake, fsi_cr_office365_agentintake.

.EXAMPLE
    ./Test-IntakeConnectionBinding.ps1 -EnvironmentUrl https://autojude.crm.dynamics.com/

    Reports every fsi_cr_* connection reference and gates on the three vertical-slice references.

.EXAMPLE
    ./Test-IntakeConnectionBinding.ps1 -EnvironmentUrl https://autojude.crm.dynamics.com/ -RequireBound fsi_cr_dataverse_agentintake,fsi_cr_teams_agentintake,fsi_cr_office365_agentintake,fsi_cr_http_agentintake,fsi_cr_graph_agentintake

    Gates on all five connection references (use once the handoff flows and their connections exist).

.NOTES
    A connection reference is considered bound when its connectionid attribute is non-empty.
    Logical names follow the agent-intake solution shell (scripts/provision_solution_shell.ps1).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [Parameter()]
    [string[]]$RequireBound = @(
        'fsi_cr_dataverse_agentintake',
        'fsi_cr_teams_agentintake',
        'fsi_cr_office365_agentintake'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Get-ConnectionReference {
    $uri = "connectionreferences?`$select=connectionreferencelogicalname,connectionreferencedisplayname,connectionid&`$filter=startswith(connectionreferencelogicalname,'fsi_cr_')"
    $absolute = '{0}/api/data/v9.2/{1}' -f $EnvironmentUrl.TrimEnd('/'), $uri
    $headers = @{
        Authorization      = "Bearer $(Get-DataverseAccessToken)"
        Accept             = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }
    $response = Invoke-RestMethod -Method GET -Uri $absolute -Headers $headers -TimeoutSec 60
    return @($response.value)
}

# --- Main ----------------------------------------------------------------------------------
Write-Host "Environment : $EnvironmentUrl" -ForegroundColor Cyan
Write-Host ("Required    : {0}" -f ($RequireBound -join ', ')) -ForegroundColor Cyan

$references = Get-ConnectionReference
$byName = @{}
foreach ($reference in $references) {
    $byName[[string]$reference.connectionreferencelogicalname] = $reference
}

$report = foreach ($reference in $references) {
    [pscustomobject]@{
        ConnectionReference = [string]$reference.connectionreferencelogicalname
        Bound               = -not [string]::IsNullOrWhiteSpace([string]$reference.connectionid)
        Required            = $RequireBound -contains [string]$reference.connectionreferencelogicalname
    }
}

if ($report) {
    Write-Host ""
    $report | Sort-Object @{ Expression = 'Required'; Descending = $true }, ConnectionReference | Format-Table -AutoSize
}

$missing = New-Object System.Collections.Generic.List[string]
foreach ($name in $RequireBound) {
    if (-not $byName.ContainsKey($name)) {
        $missing.Add("$name (reference not found)") | Out-Null
        continue
    }
    if ([string]::IsNullOrWhiteSpace([string]$byName[$name].connectionid)) {
        $missing.Add("$name (unbound)") | Out-Null
    }
}

$boundRequired = $RequireBound.Count - $missing.Count
Write-Host ("Bound       : {0} of {1} required reference(s)" -f $boundRequired, $RequireBound.Count) -ForegroundColor Cyan

if ($missing.Count -gt 0) {
    Write-Error ("Connection-binding gate FAILED. Bind the following in Solutions > Connection references:`n  - {0}" -f ($missing -join "`n  - "))
    exit 1
}

Write-Host "Connection-binding gate PASSED: all required references are bound." -ForegroundColor Green

return [pscustomobject]@{
    RequiredCount = $RequireBound.Count
    BoundCount    = $boundRequired
    AllBound      = $true
    References    = $report
}
