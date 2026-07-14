#Requires -Version 7.2
<#
.SYNOPSIS
Validates and optionally executes a typed lab harness plan.

.DESCRIPTION
Loads a typed validation plan, validates it against schema and ownership manifest contracts,
confines all referenced paths to approved roots, and executes only allow-listed adapters.
When -PlanOnly is set, no runtime or Playwright checks are executed.

.PARAMETER Solution
Canonical solution slug matching the plan and ownership manifest.

.PARAMETER PlanPath
Path to the solution validation plan JSON document.

.PARAMETER PlanOnly
Validates all plan artifacts without executing runtime or Playwright steps.

.PARAMETER EvidenceRoot
Root path for sanitized summary output. Defaults to C:\FSI-Lab-Evidence.

.EXAMPLE
pwsh .\lab-harness\runtime\Invoke-LabValidation.ps1 `
  -Solution audit-compliance-manager `
  -PlanPath .\lab-harness\templates\audit-compliance-manager.plan.json `
  -PlanOnly `
  -EvidenceRoot C:\FSI-Lab-Evidence
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Solution,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PlanPath,

    [Parameter()]
    [switch]$PlanOnly,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$EvidenceRoot = 'C:\FSI-Lab-Evidence'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'LabHarness.Runtime.psm1'
Import-Module -Name $modulePath -Force

try {
    $result = Invoke-LabValidation -Solution $Solution -PlanPath $PlanPath -PlanOnly:$PlanOnly -EvidenceRoot $EvidenceRoot
    if ($result.Result -eq 'PlanValidatedNotExecuted') {
        Write-Output ("Plan validated for solution '{0}'. No runtime checks executed. Summary: {1}" -f $Solution, $result.SummaryPath)
    }
    elseif ($result.Result -eq 'Failed') {
        Write-Output ("Validation failed for solution '{0}'. Review sanitized summary: {1}" -f $Solution, $result.SummaryPath)
    }
    else {
        Write-Output ("Validation completed for solution '{0}'. Summary: {1}" -f $Solution, $result.SummaryPath)
    }

    exit $result.ExitCode
}
catch [System.UnauthorizedAccessException] {
    Write-Error $_
    exit 11
}
catch [System.IO.InvalidDataException] {
    Write-Error $_
    exit 10
}
catch [System.IO.FileNotFoundException] {
    Write-Error $_
    exit 10
}
catch [System.InvalidOperationException] {
    Write-Error $_
    exit 20
}
catch {
    Write-Error $_
    exit 30
}
