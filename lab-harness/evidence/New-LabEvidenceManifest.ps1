#Requires -Version 7.2
<#
.SYNOPSIS
Generates a SHA-256 manifest for redacted evidence artifacts.

.DESCRIPTION
Enumerates files under the provided artifact root and writes a JSON manifest with
relative paths, byte lengths, and SHA-256 digests.

.PARAMETER ArtifactRoot
Root directory containing redacted artifacts.

.PARAMETER ManifestPath
Output path for the generated manifest JSON document.

.EXAMPLE
pwsh .\lab-harness\evidence\New-LabEvidenceManifest.ps1 `
  -ArtifactRoot .\lab-harness\evidence\redacted `
  -ManifestPath .\lab-harness\evidence\manifests\redacted.manifest.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactRoot,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'LabHarness.Evidence.psm1'
Import-Module -Name $modulePath -Force

$result = New-LabEvidenceManifest -ArtifactRoot $ArtifactRoot -ManifestPath $ManifestPath
Write-Output ($result | ConvertTo-Json -Depth 6)
