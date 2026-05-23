#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Deploys the UASD detection flow to a Power Platform environment.

.DESCRIPTION
    Deploys the Unrestricted Agent Sharing Detector detection flow
    into the target Power Platform environment using the Dataverse
    Web API solution import endpoint.

    The script authenticates via Az.Accounts and uploads a flow
    definition JSON file as a managed or unmanaged solution component.

    The -SolutionPath parameter must point to a flow definition JSON
    file exported from Power Automate. As of v1.0.1, flow JSON files
    are no longer shipped with the solution — you must first export
    the flow from your source environment (Power Automate > Solutions >
    UASD > Export) to obtain the JSON file.

.PARAMETER DataverseUrl
    Dataverse environment URL (e.g., https://org.crm.dynamics.com)

.PARAMETER SolutionPath
    Path to the detection flow JSON file

.PARAMETER TenantId
    Entra ID tenant GUID (optional, uses current Az context if omitted)

.EXAMPLE
    .\Deploy-DetectionFlow.ps1 -DataverseUrl "https://org.crm.dynamics.com" -SolutionPath ".\exported-detection-flow.json"

.EXAMPLE
    .\Deploy-DetectionFlow.ps1 -DataverseUrl "https://org.crm.dynamics.com" -SolutionPath ".\exported-detection-flow.json" -WhatIf

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

# === DEPRECATED in v2.0.0 ===
# This script attempted to deploy a cloud flow by POSTing raw JSON to the
# Dataverse `workflows` table. That is NOT a supported provisioning path —
# triggers, connection references, and solution metadata are not wired up,
# producing a non-functional flow.
#
# Per the FSI-AgentGov-Solutions content policy, cloud flows must be built
# manually. See docs/flow-configuration.md in this solution for step-by-step
# instructions.
Write-Error "This script is DEPRECATED. UASD v2.0.0+ requires building this flow manually per docs/flow-configuration.md. The Dataverse workflows POST pattern this script used is not supported by Microsoft and produces non-functional flows."
exit 2

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

$tokenResult = Get-AzAccessToken -ResourceUrl $DataverseUrl -AsSecureString
$token = $tokenResult.Token | ConvertFrom-SecureString -AsPlainText
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
$flowNameEscaped = $flowName -replace "'", "''"
$checkUrl = "$apiBase/workflows?`$filter=name eq '$flowNameEscaped'&`$select=workflowid,name,statecode"

$existing = $null
try {
    $existing = Invoke-RestMethod -Uri $checkUrl -Headers $headers -Method Get
    if ($null -ne $existing -and $existing.value.Count -gt 0) {
        $existingId = $existing.value[0].workflowid
        Write-Host "  Existing flow found: $existingId" -ForegroundColor Yellow
        Write-Host "  Flow will be updated (overwrite)"
    }
} catch {
    Write-Host "  ERROR: Failed to query existing flows: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Deploy ---
if ($PSCmdlet.ShouldProcess($flowName, "Deploy detection flow to $DataverseUrl")) {
    try {
        $importPayload = @{
            "clientdata" = $flowDefinition
            "category"   = 5  # Cloud Flow
        } | ConvertTo-Json -Depth 10

        if ($null -ne $existing -and $existing.value.Count -gt 0) {
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
