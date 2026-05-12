# Graph PowerShell Snippet — Service Health Ingestion

This document provides a complete PowerShell example for ingesting Microsoft 365 Service Health events using the Microsoft Graph PowerShell SDK (`Invoke-MgGraphRequest`) as an alternative to the Python `ingest_service_health.py` script.

## Prerequisites

| Requirement | Details |
|------------|---------|
| **PowerShell 7+** | `pwsh --version` |
| **Microsoft.Graph module** | `Install-Module Microsoft.Graph -Scope CurrentUser` |
| **Graph permission** | `ServiceHealth.Read.All` (application) |
| **Authentication** | Managed identity preferred; interactive for admin workstation |

## Complete Example

```powershell
#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Retrieves Microsoft 365 Service Health events via Microsoft Graph PowerShell SDK.

.DESCRIPTION
    Connects to Microsoft Graph using managed identity (preferred) or interactive
    browser auth, retrieves service health overviews and active issues, and writes
    structured JSON output.

    Graph endpoints:
      GET /admin/serviceAnnouncement/healthOverviews
      GET /admin/serviceAnnouncement/issues

    Required permission: ServiceHealth.Read.All

.PARAMETER OutputPath
    Path for JSON output file. If not specified, output is written to the console.

.PARAMETER AuthMode
    Authentication mode: ManagedIdentity (default), Interactive, or ClientSecret (legacy).

.PARAMETER TenantId
    Microsoft Entra tenant ID (required for Interactive and ClientSecret modes).

.PARAMETER ClientId
    Application (client) ID for ClientSecret auth mode.

.EXAMPLE
    # Managed identity (Azure-hosted automation)
    .\Get-ServiceHealth.ps1 -OutputPath .\output\service-health.json

.EXAMPLE
    # Interactive (admin workstation)
    .\Get-ServiceHealth.ps1 -AuthMode Interactive -TenantId "00000000-..." -OutputPath .\output\health.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("ManagedIdentity", "Interactive", "ClientSecret")]
    [string]$AuthMode = "ManagedIdentity",

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Authentication ───────────────────────────────────────────────────────────

$scopes = @("https://graph.microsoft.com/.default")

switch ($AuthMode) {
    "ManagedIdentity" {
        Write-Host "[INFO] Connecting with managed identity..." -ForegroundColor Cyan
        Connect-MgGraph -Identity -NoWelcome
    }
    "Interactive" {
        if (-not $TenantId) {
            Write-Error "-TenantId is required for Interactive auth mode"
            return
        }
        Write-Host "[INFO] Connecting with interactive browser auth..." -ForegroundColor Cyan
        Connect-MgGraph -TenantId $TenantId -Scopes "ServiceHealth.Read.All" -NoWelcome
    }
    "ClientSecret" {
        if (-not $TenantId -or -not $ClientId) {
            Write-Error "-TenantId and -ClientId are required for ClientSecret auth mode"
            return
        }
        # Legacy fallback — prefer managed identity in production
        $secret = $env:MCM_CLIENT_SECRET
        if (-not $secret) {
            $secret = Read-Host -AsSecureString -Prompt "Client secret"
        }
        else {
            $secret = ConvertTo-SecureString $secret -AsPlainText -Force
        }
        $cred = [PSCredential]::new($ClientId, $secret)
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $cred -NoWelcome
    }
}

Write-Host "[INFO] Connected to Microsoft Graph" -ForegroundColor Cyan

# ── Paged retrieval helper ───────────────────────────────────────────────────

function Get-GraphPaged {
    <#
    .SYNOPSIS
        Retrieves all pages from a Graph API endpoint.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Description
    )

    $allResults = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri

    while ($nextLink) {
        try {
            $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink -ErrorAction Stop
        }
        catch {
            Write-Error "${Description} failed: $_"
            return @()
        }

        $items = $response.value
        if ($items) {
            $allResults.AddRange($items)
        }

        Write-Host "[INFO]   Retrieved $($items.Count) items (total: $($allResults.Count))" -ForegroundColor Cyan
        $nextLink = $response.'@odata.nextLink'
    }

    return $allResults.ToArray()
}

# ── Retrieve data ────────────────────────────────────────────────────────────

Write-Host "[INFO] Fetching service health overviews..." -ForegroundColor Cyan
$overviews = Get-GraphPaged `
    -Uri "/admin/serviceAnnouncement/healthOverviews" `
    -Description "Health overviews"

Write-Host "[INFO] Fetching service health issues..." -ForegroundColor Cyan
$issues = Get-GraphPaged `
    -Uri "/admin/serviceAnnouncement/issues" `
    -Description "Health issues"

# ── Build output ─────────────────────────────────────────────────────────────

$activeIssues = @($issues | Where-Object { $_.status -notin @("resolved", "serviceRestored") })

$result = @{
    metadata  = @{
        generatedAt = (Get-Date -Format 'o')
        generatedBy = 'Get-ServiceHealth.ps1 (Graph PowerShell SDK)'
        graphVersion = 'v1.0'
        permission  = 'ServiceHealth.Read.All'
    }
    overviews = $overviews
    issues    = $issues
    summary   = @{
        totalServices = $overviews.Count
        totalIssues   = $issues.Count
        activeIssues  = $activeIssues.Count
    }
}

$json = $result | ConvertTo-Json -Depth 10

if ($OutputPath) {
    $dir = Split-Path $OutputPath -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json | Set-Content -Path $OutputPath -Encoding utf8
    Write-Host "[INFO] Output written to: $OutputPath" -ForegroundColor Cyan
}
else {
    Write-Output $json
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host "" -ForegroundColor Green
Write-Host "── Service Health Summary ──" -ForegroundColor Green
Write-Host "  Services monitored : $($overviews.Count)"
Write-Host "  Total issues       : $($issues.Count)"
Write-Host "  Active issues      : $($activeIssues.Count)"

# ── Disconnect ───────────────────────────────────────────────────────────────

Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
```

## Usage Notes

- **Managed identity** is the recommended authentication mode for automated/scheduled runs in Azure-hosted environments
- **Paging** is handled automatically — the `Get-GraphPaged` helper follows `@odata.nextLink` until all results are retrieved
- **Error handling** captures Graph API failures per-endpoint without terminating the entire script
- **Output format** matches the Python `ingest_service_health.py` JSON schema for interoperability

## Comparison with Python Script

| Aspect | Python (`ingest_service_health.py`) | PowerShell (`Get-ServiceHealth.ps1`) |
|--------|-------------------------------------|--------------------------------------|
| Runtime | Python 3.9+ with azure-identity | PowerShell 7+ with Microsoft.Graph module |
| Auth | azure.identity ChainedTokenCredential | Connect-MgGraph |
| HTTP | requests library | Invoke-MgGraphRequest (built-in) |
| Best for | Azure Functions, container workloads | Admin workstations, Azure Automation runbooks |

Choose the version that best fits your automation runtime. Both produce identical JSON output.
