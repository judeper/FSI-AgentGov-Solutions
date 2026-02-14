#Requires -Version 7.0

<#
.SYNOPSIS
    Creates a scope baseline for an AI agent.

.DESCRIPTION
    Captures the current data access scope for an agent by analyzing
    CopilotInteraction events from the Office 365 Management API (Unified Audit Log)
    and creates a scope definition in Dataverse.

.PARAMETER AgentId
    The Copilot Studio agent ID.

.PARAMETER Environment
    The Dataverse environment URL.

.PARAMETER Days
    Number of days of audit history to analyze (default: 30).

.PARAMETER TenantId
    Azure AD tenant ID. Defaults to AZURE_TENANT_ID environment variable.

.PARAMETER ClientId
    Azure AD application client ID. Defaults to AZURE_CLIENT_ID environment variable.

.PARAMETER ClientSecret
    Azure AD application client secret. Defaults to AZURE_CLIENT_SECRET environment variable.

.EXAMPLE
    .\New-AgentBaseline.ps1 -AgentId "12345678-..." -Environment "https://contoso.crm.dynamics.com"

.EXAMPLE
    .\New-AgentBaseline.ps1 -AgentId "12345678-..." -Environment "https://contoso.crm.dynamics.com" -Days 60

.NOTES
    Requires:
    - Azure AD application with Office 365 Management APIs permissions (ActivityFeed.Read)
    - Azure AD application with Dataverse permissions
    - Microsoft 365 E5 or E5 Compliance license for CopilotInteraction events
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AgentId,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [int]$Days = 30,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = $env:AZURE_CLIENT_SECRET
)

$ErrorActionPreference = "Stop"

#region Helper Functions

function Get-AccessToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,

        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = "client_credentials"
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        return $response.access_token
    }
    catch {
        throw "Failed to acquire access token for scope '$Scope': $($_.Exception.Message)"
    }
}

function Get-CopilotAuditEvents {
    <#
    .SYNOPSIS
        Queries Office 365 Management API for CopilotInteraction events.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$AgentId,

        [Parameter(Mandatory = $true)]
        [int]$Days
    )

    $events = @()
    $startDate = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    $endDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    # Ensure subscription is active
    try {
        $subscriptionUri = "https://manage.office.com/api/v1.0/$TenantId/activity/feed/subscriptions/start?contentType=Audit.General"
        $null = Invoke-RestMethod -Uri $subscriptionUri -Method Post -Headers $headers -ErrorAction SilentlyContinue
    }
    catch {
        # 400 error means already subscribed, which is fine
        if ($_.Exception.Response.StatusCode -ne 400) {
            Write-Warning "Could not start audit subscription: $($_.Exception.Message)"
        }
    }

    # Get content blobs for the time period
    $contentUri = "https://manage.office.com/api/v1.0/$TenantId/activity/feed/subscriptions/content?contentType=Audit.General&startTime=$startDate&endTime=$endDate"

    try {
        $contentBlobs = @()
        $nextPageUri = $contentUri

        # Handle pagination via NextPageUri header
        while ($nextPageUri) {
            $response = Invoke-WebRequest -Uri $nextPageUri -Headers $headers -Method Get
            $blobs = $response.Content | ConvertFrom-Json
            if ($blobs) {
                $contentBlobs += $blobs
            }

            # Check for next page
            $nextPageUri = $null
            if ($response.Headers["NextPageUri"]) {
                $nextPageUri = $response.Headers["NextPageUri"]
            }
        }

        Write-Host "  Found $($contentBlobs.Count) content blobs to process"

        # Fetch each content blob and filter for CopilotInteraction (RecordType 261)
        foreach ($blob in $contentBlobs) {
            try {
                $blobEvents = Invoke-RestMethod -Uri $blob.contentUri -Headers $headers -Method Get

                # Filter for CopilotInteraction events (RecordType 261)
                # and optionally filter by agent ID if event contains it
                $copilotEvents = $blobEvents | Where-Object {
                    $_.RecordType -eq 261 -and
                    $_.EventData.AgentId -eq $AgentId
                }

                $events += $copilotEvents
            }
            catch {
                Write-Warning "Could not fetch content blob: $($_.Exception.Message)"
            }
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 403) {
            Write-Warning "Access denied to Office 365 Management API. Ensure E5/E5 Compliance license is assigned and ActivityFeed.Read permission is granted."
        }
        else {
            Write-Warning "Could not query audit content: $($_.Exception.Message)"
        }
    }

    return $events
}

function Analyze-AccessedResources {
    <#
    .SYNOPSIS
        Parses CopilotInteraction AccessedResources into categorized resources.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Events
    )

    $resources = @{
        Connectors = @()
        Sites      = @()
        Tables     = @()
        APIs       = @()
    }

    foreach ($event in $Events) {
        $eventData = $event.EventData

        # Extract connectors from AISystemPlugin array
        if ($eventData.AISystemPlugin) {
            foreach ($plugin in $eventData.AISystemPlugin) {
                if ($plugin.Name -and $plugin.Enabled -eq $true) {
                    $connectorName = $plugin.Name -replace "Connector$", ""
                    if ($connectorName -notin $resources.Connectors) {
                        $resources.Connectors += $connectorName
                    }
                }
            }
        }

        # Extract SharePoint sites from Contexts array
        if ($eventData.Contexts) {
            foreach ($context in $eventData.Contexts) {
                if ($context.Id -match "sharepoint\.com") {
                    # Extract site URL from full document path
                    if ($context.Id -match "(https://[^/]+\.sharepoint\.com/sites/[^/]+)") {
                        $siteUrl = $Matches[1]
                        if ($siteUrl -notin $resources.Sites) {
                            $resources.Sites += $siteUrl
                        }
                    }
                }
            }
        }

        # Extract from AccessedResources array
        if ($eventData.AccessedResources) {
            foreach ($resource in $eventData.AccessedResources) {
                # SharePoint sites
                if ($resource.SiteUrl -and $resource.SiteUrl -notin $resources.Sites) {
                    $resources.Sites += $resource.SiteUrl
                }

                # Identify Dataverse tables from resource type
                if ($resource.Type -eq "DataverseTable" -or $resource.Type -eq "Table") {
                    if ($resource.Name -notin $resources.Tables) {
                        $resources.Tables += $resource.Name
                    }
                }

                # Identify external APIs from resource URL patterns
                if ($resource.Type -eq "ExternalAPI" -or
                    ($resource.Id -match "^https?://" -and $resource.Id -notmatch "(sharepoint|microsoft|office)\.com")) {
                    $apiUrl = $resource.Id
                    if ($apiUrl -notin $resources.APIs) {
                        $resources.APIs += $apiUrl
                    }
                }
            }
        }
    }

    return $resources
}

function Build-ScopeFromHistory {
    <#
    .SYNOPSIS
        Aggregates unique resources from analysis window into scope definition.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Resources,

        [Parameter(Mandatory = $true)]
        [string]$AgentId
    )

    $scope = @{
        fsi_name              = "Agent $AgentId Baseline"
        fsi_agentid           = $AgentId
        fsi_zone              = 2  # Default to Zone 2
        fsi_status            = 2  # Active (auto-generated baseline goes active immediately per CONTEXT.md)
        fsi_purpose           = "Auto-generated baseline from $Days-day audit history analysis"
        fsi_allowedconnectors = ($Resources.Connectors | ConvertTo-Json -Compress)
        fsi_allowedsites      = ($Resources.Sites | ConvertTo-Json -Compress)
        fsi_allowedtables     = ($Resources.Tables | ConvertTo-Json -Compress)
        fsi_allowedapis       = ($Resources.APIs | ConvertTo-Json -Compress)
        fsi_lastvalidated     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    # Handle empty arrays (ensure valid JSON)
    if ($Resources.Connectors.Count -eq 0) { $scope.fsi_allowedconnectors = "[]" }
    if ($Resources.Sites.Count -eq 0) { $scope.fsi_allowedsites = "[]" }
    if ($Resources.Tables.Count -eq 0) { $scope.fsi_allowedtables = "[]" }
    if ($Resources.APIs.Count -eq 0) { $scope.fsi_allowedapis = "[]" }

    return $scope
}

function Create-ScopeDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scope
    )

    $headers = @{
        "Authorization"    = "Bearer $Token"
        "Content-Type"     = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
    }

    $uri = "$Environment/api/data/v9.2/fsi_agentscopes"
    $body = $Scope | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body
        return $response
    }
    catch {
        throw "Failed to create scope definition in Dataverse: $($_.Exception.Message)"
    }
}

#endregion

#region Main Script

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Agent Scope Baseline Generator" -ForegroundColor Cyan
Write-Host "  (Office 365 Management API)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Agent ID: $AgentId"
Write-Host "Environment: $Environment"
Write-Host "Analysis Period: $Days days"
Write-Host ""

# Validate credentials
if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Error "Missing credentials. Set environment variables: AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET"
    exit 1
}

# Get tokens for Office 365 Management API and Dataverse
Write-Host "Authenticating..." -ForegroundColor Gray

try {
    $managementToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "https://manage.office.com/.default"
    Write-Host "  Office 365 Management API: authenticated" -ForegroundColor Green
}
catch {
    Write-Error "Failed to authenticate to Office 365 Management API: $($_.Exception.Message)"
    exit 1
}

try {
    $dataverseToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default"
    Write-Host "  Dataverse: authenticated" -ForegroundColor Green
}
catch {
    Write-Error "Failed to authenticate to Dataverse: $($_.Exception.Message)"
    exit 1
}

# Get CopilotInteraction audit events
Write-Host ""
Write-Host "Querying Office 365 Management API for CopilotInteraction events..." -ForegroundColor Gray
$events = Get-CopilotAuditEvents -Token $managementToken -TenantId $TenantId -AgentId $AgentId -Days $Days
Write-Host "  Found $($events.Count) CopilotInteraction events (RecordType 261)"

# Analyze accessed resources
Write-Host ""
Write-Host "Analyzing accessed resources..." -ForegroundColor Gray
$resources = Analyze-AccessedResources -Events $events

Write-Host "  Connectors: $($resources.Connectors.Count) unique ($($resources.Connectors -join ', '))"
Write-Host "  SharePoint Sites: $($resources.Sites.Count) unique"
Write-Host "  Dataverse Tables: $($resources.Tables.Count) unique ($($resources.Tables -join ', '))"
Write-Host "  External APIs: $($resources.APIs.Count) unique"

# Build scope definition
Write-Host ""
Write-Host "Building scope definition..." -ForegroundColor Gray
$scopeDefinition = Build-ScopeFromHistory -Resources $resources -AgentId $AgentId

if ($events.Count -eq 0) {
    Write-Host "  No audit events found - creating empty baseline" -ForegroundColor Yellow
    Write-Host "  (New agent will be monitored for any data access)" -ForegroundColor Yellow
}
else {
    Write-Host "  Scope built from $($events.Count) events" -ForegroundColor Green
}

# Create scope in Dataverse
Write-Host ""
Write-Host "Creating scope definition in Dataverse..." -ForegroundColor Gray

try {
    $result = Create-ScopeDefinition -Environment $Environment -Token $dataverseToken -Scope $scopeDefinition
    Write-Host "  Scope created successfully" -ForegroundColor Green
    Write-Host "  Scope ID: $($result.fsi_agentscopeid)"
    Write-Host "  Status: Active (monitoring enabled)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to create scope definition: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Baseline Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:"
Write-Host "  - Agent ID: $AgentId"
Write-Host "  - Events analyzed: $($events.Count)"
Write-Host "  - Connectors: $($resources.Connectors.Count)"
Write-Host "  - SharePoint Sites: $($resources.Sites.Count)"
Write-Host "  - Dataverse Tables: $($resources.Tables.Count)"
Write-Host "  - External APIs: $($resources.APIs.Count)"
Write-Host ""
Write-Host "The baseline is now active. Any data access outside this scope will trigger a drift violation."
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Review the generated scope definition in Dataverse"
Write-Host "2. Run Invoke-DriftScan.ps1 to test detection"
Write-Host "3. Configure detection flows for continuous monitoring"

#endregion
