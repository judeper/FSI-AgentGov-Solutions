<#
.SYNOPSIS
    Captures and exports a Conditional Access policy baseline snapshot to JSON.

.DESCRIPTION
    Orchestrates baseline capture by connecting to Microsoft Graph, querying
    all Conditional Access policies matching FSI governance naming patterns,
    and exporting the normalized results to a JSON file with a metadata envelope.

    The exported baseline includes a metadata header (capture timestamp, operator,
    tenant ID, policy count, schema version) and the full array of normalized
    policy objects. This baseline file serves as the reference point for
    subsequent drift detection via Watch-PolicyDrift.ps1.

    Supports WhatIf mode to preview the capture operation without querying Graph.

.PARAMETER TenantId
    The Entra ID tenant GUID to capture policies from.

.PARAMETER OutputPath
    File path for the exported JSON baseline. The directory is created
    automatically if it does not exist.

.PARAMETER ConfigPath
    Optional path to a tenant configuration JSON file containing group IDs,
    application IDs, break-glass accounts, and an optional policyPrefix.

.PARAMETER OutputFormat
    Format for console summary output. Valid values: Table (default), JSON, Object.
    Table renders a formatted summary; JSON writes the baseline to stdout;
    Object returns the baseline hashtable for pipeline processing.

.EXAMPLE
    .\Export-PolicyBaseline.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -OutputPath "./baselines/baseline.json"

    Captures the current CA policy state and writes the baseline to the specified path.

.EXAMPLE
    .\Export-PolicyBaseline.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -OutputPath "./baseline.json" -ConfigPath "./config.json"

    Captures policies including any custom policyPrefix from the config file.

.EXAMPLE
    .\Export-PolicyBaseline.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -OutputPath "./baseline.json" -WhatIf

    Previews what would be captured without connecting to Graph.

.OUTPUTS
    System.Collections.Hashtable
    When -OutputFormat is 'Object', returns the baseline envelope hashtable.

.NOTES
    File: Export-PolicyBaseline.ps1
    Version: 1.0.0
    Supports compliance with FINRA 4511/3110, SEC 17a-3/4, and OCC 2011-12
    through automated baseline capture for policy drift detection.
#>

#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Table", "JSON", "Object")]
    [string]$OutputFormat = "Table"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import private helpers
. $PSScriptRoot/private/Connect-GraphSession.ps1
. $PSScriptRoot/private/Get-PolicyBaseline.ps1

Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "CA Policy Baseline Export" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host ""

# WhatIf preview
if ($WhatIfPreference) {
    Write-Host "[WhatIf] Would perform the following:" -ForegroundColor Yellow
    Write-Host "  1. Connect to Microsoft Graph (Tenant: $TenantId)"
    Write-Host "  2. Query CA policies matching FSI naming patterns"
    if ($ConfigPath) {
        Write-Host "  3. Include custom prefix from config: $ConfigPath"
    }
    Write-Host "  4. Export baseline JSON to: $OutputPath"
    Write-Host "  Output format: $OutputFormat"
    return
}

# Ensure output directory exists
$outputDir = Split-Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Verbose "Created output directory: $outputDir"
}

# Connect to Microsoft Graph
Write-Verbose "Establishing Microsoft Graph session..."
Connect-CAAGraphSession -TenantId $TenantId -Scopes @('Policy.Read.All')
Write-Verbose "Connected."

# Capture baseline snapshot
Write-Verbose "Capturing policy baseline..."
$baselineParams = @{}
if ($TenantId) { $baselineParams['TenantId'] = $TenantId }
if ($ConfigPath) { $baselineParams['ConfigPath'] = $ConfigPath }

$policies = Get-CAAPolicyBaseline @baselineParams

# Get operator identity
$capturedBy = 'unknown'
try {
    $mgContext = Get-MgContext
    if ($mgContext -and $mgContext.Account) {
        $capturedBy = $mgContext.Account
    }
}
catch {
    Write-Verbose "Could not determine operator identity: $_"
}

# Determine zones covered
$zonesCovered = @($policies | ForEach-Object {
    if ($_ -is [hashtable]) { $_.Zone } else { $_.zone }
} | Sort-Object -Unique)

# Build baseline envelope
$baseline = @{
    metadata = @{
        capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
        capturedBy    = $capturedBy
        tenantId      = $TenantId
        policyCount   = $policies.Count
        schemaVersion = '1.0'
    }
    policies = @($policies)
}

# Write to file
$jsonContent = $baseline | ConvertTo-Json -Depth 15
$jsonContent | Out-File -FilePath $OutputPath -Encoding utf8 -Force
Write-Verbose "Baseline written to: $OutputPath"

# Console summary
Write-Host ""
Write-Host "Baseline Captured Successfully" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  Policies captured:  $($policies.Count)"
Write-Host "  Zones covered:      $($zonesCovered -join ', ')"
Write-Host "  Output file:        $OutputPath"
Write-Host "  Captured by:        $capturedBy"
Write-Host "  Timestamp:          $($baseline.metadata.capturedAt)"
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

# Output results based on format
switch ($OutputFormat) {
    "JSON" {
        $jsonContent
    }
    "Object" {
        $baseline
    }
    # "Table" — already displayed summary above
}

Write-Host "Baseline export complete." -ForegroundColor Green
