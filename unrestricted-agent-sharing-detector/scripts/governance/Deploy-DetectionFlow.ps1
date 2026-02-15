#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Deploys the UASD detection flow to a Power Platform environment.

.DESCRIPTION
    Imports the Unrestricted Agent Sharing Detector detection flow
    (uasd-detector-scan-agents.json) into the target Power Platform
    environment using the Dataverse Web API solution import endpoint.

    The script authenticates via Az.Accounts and uploads the flow
    definition as a managed or unmanaged solution component.

.PARAMETER DataverseUrl
    Dataverse environment URL (e.g., https://org.crm.dynamics.com)

.PARAMETER SolutionPath
    Path to the detection flow JSON file

.PARAMETER TenantId
    Entra ID tenant GUID (optional, uses current Az context if omitted)

.EXAMPLE
    .\Deploy-DetectionFlow.ps1 -DataverseUrl "https://org.crm.dynamics.com" -SolutionPath "..\..\src\uasd-detector-scan-agents.json"

.EXAMPLE
    .\Deploy-DetectionFlow.ps1 -DataverseUrl "https://org.crm.dynamics.com" -SolutionPath "..\..\src\uasd-detector-scan-agents.json" -WhatIf

.NOTES
    FSI Agent Governance Framework - Unrestricted Agent Sharing Detector
    Requires: Az.Accounts module, Dataverse System Administrator role
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$SolutionPath,

    [Parameter()]
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Authentication ---
Write-Host "`n[UASD Detection Flow Deployment]" -ForegroundColor Cyan
Write-Host "  Target: $DataverseUrl"

if (-not (Get-AzContext)) {
    Write-Host "  Authenticating with Az.Accounts..." -ForegroundColor Yellow
    if ($TenantId) {
        Connect-AzAccount -TenantId $TenantId | Out-Null
    } else {
        Connect-AzAccount | Out-Null
    }
}

$token = (Get-AzAccessToken -ResourceUrl $DataverseUrl).Token
$headers = @{
    "Authorization"    = "Bearer $token"
    "Content-Type"     = "application/json"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "Accept"           = "application/json"
}

# --- Validate Solution File ---
Write-Host "  Reading: $SolutionPath"
$flowDefinition = Get-Content -Path $SolutionPath -Raw
$flowJson = $flowDefinition | ConvertFrom-Json

if (-not $flowJson) {
    Write-Host "  ERROR: Failed to parse flow definition JSON" -ForegroundColor Red
    exit 1
}

$flowName = $flowJson.properties.displayName ?? "UASD-Detector-Scan-Agents"
Write-Host "  Flow: $flowName"

# --- Check Existing ---
$apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
$checkUrl = "$apiBase/workflows?`$filter=name eq '$flowName'&`$select=workflowid,name,statecode"

try {
    $existing = Invoke-RestMethod -Uri $checkUrl -Headers $headers -Method Get
    if ($existing.value.Count -gt 0) {
        $existingId = $existing.value[0].workflowid
        Write-Host "  Existing flow found: $existingId" -ForegroundColor Yellow
        Write-Host "  Flow will be updated (overwrite)"
    }
} catch {
    Write-Host "  No existing flow found, creating new" -ForegroundColor Green
}

# --- Deploy ---
if ($PSCmdlet.ShouldProcess($flowName, "Deploy detection flow to $DataverseUrl")) {
    try {
        $importPayload = @{
            "clientdata" = $flowDefinition
            "category"   = 5  # Cloud Flow
        } | ConvertTo-Json -Depth 10

        if ($existing.value.Count -gt 0) {
            # Update existing
            $updateUrl = "$apiBase/workflows($existingId)"
            Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method Patch -Body $importPayload
            Write-Host "  Updated: $flowName ($existingId)" -ForegroundColor Green
        } else {
            # Create new
            $createUrl = "$apiBase/workflows"
            $result = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method Post -Body $importPayload
            $newId = $result.workflowid
            Write-Host "  Created: $flowName ($newId)" -ForegroundColor Green
        }

        Write-Host "`n  Deployment: SUCCEEDED" -ForegroundColor Green
        Write-Host "  Next steps:"
        Write-Host "    1. Open Power Automate > Solutions > UASD"
        Write-Host "    2. Bind connection references (Dataverse, Teams)"
        Write-Host "    3. Configure scan schedule via fsi_UASD_ScanFrequencyHours"
        Write-Host "    4. Turn on the flow"
    } catch {
        Write-Host "  Deployment: FAILED" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($errorBody.error.message) {
                Write-Host "  Detail: $($errorBody.error.message)" -ForegroundColor Red
            }
        }
        exit 1
    }
} else {
    Write-Host "  [WhatIf] Would deploy: $flowName" -ForegroundColor Yellow
    Write-Host "  [WhatIf] Target: $DataverseUrl" -ForegroundColor Yellow
    Write-Host "  [WhatIf] Source: $SolutionPath" -ForegroundColor Yellow
}
