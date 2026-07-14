#Requires -Version 7.2
<#
.SYNOPSIS
Redacts sensitive identifiers from a text evidence artifact.

.DESCRIPTION
Applies deterministic regex-based redaction for common sensitive patterns including
UPNs, tenant domains, GUIDs, Dynamics environment URLs, webhook URLs, and token-like
query parameter values.

.PARAMETER InputPath
Path to a source evidence file to redact.

.PARAMETER OutputPath
Path where the redacted output file is written.

.EXAMPLE
pwsh .\lab-harness\evidence\Invoke-LabEvidenceRedaction.ps1 `
  -InputPath .\lab-harness\evidence\raw\sample.txt `
  -OutputPath .\lab-harness\evidence\redacted\sample.redacted.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'LabHarness.Evidence.psm1'
Import-Module -Name $modulePath -Force

$result = Invoke-LabEvidenceRedaction -InputPath $InputPath -OutputPath $OutputPath
Write-Output ($result | ConvertTo-Json -Depth 6)
