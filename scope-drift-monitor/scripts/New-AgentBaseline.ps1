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

.PARAMETER EnvironmentId
    The Power Platform environment ID (GUID) for the agent.

.PARAMETER OwnerId
    The Dataverse systemuser ID (GUID) of the agent owner.

.PARAMETER Days
    Number of days of audit history to analyze (default: 7, max: 7).
    The Office 365 Management API requires startTime within 7 days of current
    time and limits each request to a 24-hour window. The script automatically
    breaks the requested range into 24-hour windows.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Defaults to AZURE_TENANT_ID environment variable.

.PARAMETER ClientId
    Microsoft Entra ID application client ID. Defaults to AZURE_CLIENT_ID environment variable.

.PARAMETER ClientSecret
    Legacy dev-only Microsoft Entra ID application client secret. Defaults to AZURE_CLIENT_SECRET environment variable. Production automation should use managed identity.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID. Defaults to AZURE_MANAGED_IDENTITY_CLIENT_ID. If omitted, system-assigned managed identity is used when available.

.EXAMPLE
    .\New-AgentBaseline.ps1 -AgentId "12345678-..." -Environment "https://contoso.crm.dynamics.com" -EnvironmentId "env-guid" -OwnerId "user-guid"

.EXAMPLE
    .\New-AgentBaseline.ps1 -AgentId "12345678-..." -Environment "https://contoso.crm.dynamics.com" -EnvironmentId "env-guid" -OwnerId "user-guid" -Days 5

.NOTES
    Requires:
    - Microsoft Entra ID application with Office 365 Management APIs permissions (ActivityFeed.Read)
    - Microsoft Entra ID application with Dataverse permissions
    - Microsoft 365 E5 or E5 Compliance license for CopilotInteraction events
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Dev-only legacy auth path. Production deployments use managed identity via scripts/shared/dataverse_client.py per AGENTS.md "Authentication standard". Plaintext secret here is wrapped immediately into SecureString and never persisted.'
)]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AgentId,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $true)]
    [string]$OwnerId,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 7)]
    [int]$Days = 7,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [securestring]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidateSet("https://manage.office.com", "https://manage-gcc.office.com", "https://manage.office365.us", "https://manage.protection.apps.mil")]
    [string]$ManagementApiEndpoint = "https://manage.office.com",

    [Parameter(Mandatory = $false)]
    [ValidateRange(10001,10003)]
    [int]$Zone = 10002,

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityClientId = $env:AZURE_MANAGED_IDENTITY_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDuplicateCheck
)

$ErrorActionPreference = "Stop"

# Convert environment variable to SecureString if parameter not provided
if (-not $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    $ClientSecret = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
}

#region Helper Functions

function Convert-ScopeToResource {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    if ($Scope.EndsWith("/.default", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Scope.Substring(0, $Scope.Length - "/.default".Length)
    }

    return $Scope
}

function Get-ManagedIdentityAccessToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Resource,

        [Parameter(Mandatory = $false)]
        [string]$ClientId
    )

    $encodedResource = [System.Uri]::EscapeDataString($Resource)
    $encodedClientId = if ($ClientId) { [System.Uri]::EscapeDataString($ClientId) } else { $null }

    try {
        if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
            $uri = "$($env:IDENTITY_ENDPOINT)?api-version=2019-08-01&resource=$encodedResource"
            if ($encodedClientId) { $uri = "$uri&client_id=$encodedClientId" }
            $headers = @{ "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER }
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 10
            return $response.access_token
        }

        if ($env:MSI_ENDPOINT -and $env:MSI_SECRET) {
            $uri = "$($env:MSI_ENDPOINT)?api-version=2017-09-01&resource=$encodedResource"
            if ($encodedClientId) { $uri = "$uri&clientid=$encodedClientId" }
            $headers = @{ Secret = $env:MSI_SECRET }
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 10
            return $response.access_token
        }

        $imdsUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$encodedResource"
        if ($encodedClientId) { $imdsUri = "$imdsUri&client_id=$encodedClientId" }
        $imdsHeaders = @{ Metadata = "true" }
        $response = Invoke-RestMethod -Uri $imdsUri -Headers $imdsHeaders -Method Get -TimeoutSec 2
        return $response.access_token
    }
    catch {
        return $null
    }
}

function Get-AccessToken {
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId,

        [Parameter(Mandatory = $false)]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [securestring]$ClientSecret,

        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $false)]
        [string]$ManagedIdentityClientId
    )

    $resource = Convert-ScopeToResource -Scope $Scope
    $managedIdentityToken = Get-ManagedIdentityAccessToken -Resource $resource -ClientId $ManagedIdentityClientId
    if ($managedIdentityToken) {
        return $managedIdentityToken
    }

    if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
        throw "Managed identity authentication was unavailable and client-secret fallback parameters were incomplete. For production, run from an Azure host with a system-assigned or user-assigned managed identity."
    }

    # legacy: dev-only -- replace with managed identity in production
    $loginEndpoint = switch -Wildcard ($Scope) {
        "*office365.us*"        { "https://login.microsoftonline.us" }
        "*protection.apps.mil*" { "https://login.microsoftonline.us" }
        default                 { "https://login.microsoftonline.com" }
    }
    $tokenUrl = "$loginEndpoint/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = [System.Net.NetworkCredential]::new('', $ClientSecret).Password
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

function Get-CopilotEventData {
    <#
    .SYNOPSIS
        Returns the Copilot interaction payload from current and legacy audit shapes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Event
    )

    if ($Event.CopilotEventData) {
        if ($Event.CopilotEventData -is [string]) { return ($Event.CopilotEventData | ConvertFrom-Json) }
        return $Event.CopilotEventData
    }
    if ($Event.EventData) {
        if ($Event.EventData -is [string]) { return ($Event.EventData | ConvertFrom-Json) }
        return $Event.EventData
    }

    if ($Event.AuditData) {
        try {
            $auditData = if ($Event.AuditData -is [string]) { $Event.AuditData | ConvertFrom-Json } else { $Event.AuditData }
            if ($auditData.CopilotEventData) { return $auditData.CopilotEventData }
            if ($auditData.EventData) { return $auditData.EventData }
        }
        catch {
            Write-Warning "Could not parse AuditData JSON for audit record '$($Event.Id)': $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{}
}

function Get-CopilotAgentId {
    <#
    .SYNOPSIS
        Extracts agent identity from current Copilot, Copilot Studio, and legacy audit fields.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Event
    )

    $eventData = Get-CopilotEventData -Event $Event
    $auditData = $null
    if ($Event.AuditData) {
        try {
            $auditData = if ($Event.AuditData -is [string]) { $Event.AuditData | ConvertFrom-Json } else { $Event.AuditData }
        }
        catch {
            $auditData = $null
        }
    }

    $candidates = @(
        $Event.AgentId,
        $Event.BotId,
        $Event.AppIdentity,
        $auditData.AgentId,
        $auditData.BotId,
        $auditData.AppIdentity,
        $eventData.AgentId,
        $eventData.BotId,
        $eventData.AppIdentity
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
            return [string]$candidate
        }
    }

    return $null
}

function Test-AgentIdMatch {
    param(
        [Parameter(Mandatory = $false)]
        [string]$EventAgentId,

        [Parameter(Mandatory = $false)]
        [string]$ExpectedAgentId
    )

    if ([string]::IsNullOrWhiteSpace($EventAgentId) -or [string]::IsNullOrWhiteSpace($ExpectedAgentId)) {
        return $false
    }

    if ($EventAgentId.Equals($ExpectedAgentId, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return ($EventAgentId.IndexOf($ExpectedAgentId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $ExpectedAgentId.IndexOf($EventAgentId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Get-ResourceUri {
    param(
        [Parameter(Mandatory = $true)]
        $Resource
    )

    foreach ($propertyName in @('SiteUrl', 'Url', 'URL', 'Id', 'ID')) {
        if ($Resource.PSObject.Properties.Name -contains $propertyName) {
            $value = $Resource.$propertyName
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }

    return $null
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
    $rangeStart = (Get-Date).AddDays(-$Days).ToUniversalTime()
    $rangeEnd = (Get-Date).ToUniversalTime()

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    # Ensure subscription is active.
    # Note: -ErrorAction SilentlyContinue would suppress the terminating error and the
    # catch block would never run, masking real failures (403, 5xx). Let the catch fire.
    try {
        $subscriptionUri = "$ManagementApiEndpoint/api/v1.0/$TenantId/activity/feed/subscriptions/start?contentType=Audit.General"
        $null = Invoke-RestMethod -Uri $subscriptionUri -Method Post -Headers $headers
    }
    catch {
        # 400 error means already subscribed, which is fine
        if ($_.Exception.Response.StatusCode -ne 400) {
            Write-Warning "Could not start audit subscription: $($_.Exception.Message)"
        }
    }

    # Break the requested range into 24-hour windows (API constraint)
    $windowStart = $rangeStart
    while ($windowStart -lt $rangeEnd) {
        $windowEnd = $windowStart.AddHours(24)
        if ($windowEnd -gt $rangeEnd) { $windowEnd = $rangeEnd }

        $startDate = $windowStart.ToString("yyyy-MM-ddTHH:mm:ss")
        $endDate = $windowEnd.ToString("yyyy-MM-ddTHH:mm:ss")

        Write-Host "  Querying window: $startDate to $endDate" -ForegroundColor Gray

        # Get content blobs for this 24-hour window
        $contentUri = "$ManagementApiEndpoint/api/v1.0/$TenantId/activity/feed/subscriptions/content?contentType=Audit.General&startTime=$startDate&endTime=$endDate"

        try {
            $contentBlobs = @()
            $nextPageUri = $contentUri

            # Handle pagination via NextPageUri header
            while ($nextPageUri) {
                # Validate pagination URL host
                if ($nextPageUri -notmatch "^$([regex]::Escape($ManagementApiEndpoint))/") {
                    Write-Warning "Skipping untrusted pagination URL: $nextPageUri"
                    break
                }
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

            Write-Host "  Found $($contentBlobs.Count) content blobs in window"

            # Fetch each content blob and filter for CopilotInteraction (RecordType 261)
            foreach ($blob in $contentBlobs) {
                try {
                    # Validate content blob URI host
                    if ($blob.contentUri -notmatch "^$([regex]::Escape($ManagementApiEndpoint))/") {
                        Write-Warning "Skipping untrusted content URI: $($blob.contentUri)"
                        continue
                    }
                    $blobEvents = Invoke-RestMethod -Uri $blob.contentUri -Headers $headers -Method Get

                    # Filter for CopilotInteraction events (RecordType 261)
                    # and optionally filter by agent ID if event contains it
                    $copilotEvents = $blobEvents | Where-Object {
                        $_.RecordType -eq 261 -and
                        (Test-AgentIdMatch -EventAgentId (Get-CopilotAgentId -Event $_) -ExpectedAgentId $AgentId)
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
                Write-Warning "Could not query audit content for window $startDate to ${endDate}: $($_.Exception.Message)"
            }
        }

        $windowStart = $windowEnd
    }  # end while (24-hour window loop)

    return $events
}

function Get-AccessedResources {
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

    foreach ($auditEvent in $Events) {
        $eventData = Get-CopilotEventData -Event $auditEvent

        # Extract connectors from AISystemPlugin array
        if ($eventData.AISystemPlugin) {
            foreach ($plugin in @($eventData.AISystemPlugin)) {
                # .Id is the connector/plugin identity (e.g. "BingWebSearch"); .Name is the
                # plugin type (e.g. "BuiltIn"). Prefer .Id; fall back to .Name if absent.
                # Ref: https://learn.microsoft.com/office/office-365-management-api/copilot-schema
                $connectorName = if ($plugin.Id) { $plugin.Id } else { $plugin.Name }
                if ($connectorName) {
                    if ($connectorName -notin $resources.Connectors) {
                        $resources.Connectors += $connectorName
                    }
                }
            }
        }

        # Extract SharePoint sites from Contexts array
        if ($eventData.Contexts) {
            foreach ($context in @($eventData.Contexts)) {
                if ($context.Id -match "sharepoint\.com") {
                    # Extract site URL from full document path
                    if ($context.Id -match "(https://[^/]+\.sharepoint\.com/(?:sites|teams)/[^/]+)") {
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
            foreach ($resource in @($eventData.AccessedResources)) {
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
                $resourceUri = Get-ResourceUri -Resource $resource
                if ($resource.Type -eq "ExternalAPI" -or
                    ($resourceUri -match "^https?://" -and $resourceUri -notmatch "(sharepoint|microsoft|office)\.com")) {
                    if ($resourceUri -and $resourceUri -notin $resources.APIs) {
                        $resources.APIs += $resourceUri
                    }
                }
            }
        }
    }

    return $resources
}

function Get-ScopeFromHistory {
    <#
    .SYNOPSIS
        Aggregates unique resources from analysis window into scope definition.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Resources,

        [Parameter(Mandatory = $true)]
        [string]$AgentId,

        [Parameter(Mandatory = $true)]
        [string]$EnvironmentId,

        [Parameter(Mandatory = $true)]
        [string]$OwnerId,

        [ValidateRange(10001,10003)]
        [int]$Zone = 10002
    )

    $scope = @{
        fsi_name                    = "Agent $AgentId Baseline"
        fsi_agentid                 = $AgentId
        fsi_environmentid           = $EnvironmentId
        "fsi_owner@odata.bind"      = "/systemusers($OwnerId)"
        fsi_zone                    = $Zone
        fsi_status                  = [int]$(if ($env:fsi_SDM_ActiveScopeStatus) { $env:fsi_SDM_ActiveScopeStatus } else { 10002 })
        fsi_purpose                 = "Auto-generated baseline from $Days-day audit history analysis"
        fsi_allowedconnectors = (ConvertTo-Json -InputObject @($Resources.Connectors) -Compress)
        fsi_allowedsites      = (ConvertTo-Json -InputObject @($Resources.Sites) -Compress)
        fsi_allowedtables     = (ConvertTo-Json -InputObject @($Resources.Tables) -Compress)
        fsi_allowedapis       = (ConvertTo-Json -InputObject @($Resources.APIs) -Compress)
        fsi_lastvalidated     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    # Handle empty arrays (ensure valid JSON)
    if ($Resources.Connectors.Count -eq 0) { $scope.fsi_allowedconnectors = "[]" }
    if ($Resources.Sites.Count -eq 0) { $scope.fsi_allowedsites = "[]" }
    if ($Resources.Tables.Count -eq 0) { $scope.fsi_allowedtables = "[]" }
    if ($Resources.APIs.Count -eq 0) { $scope.fsi_allowedapis = "[]" }

    return $scope
}

function New-ScopeDefinition {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
    $target = if ($Scope.fsi_agentid) { $Scope.fsi_agentid } else { 'fsi_agentscopes' }

    if (-not $PSCmdlet.ShouldProcess($target, 'Create agent scope definition')) {
        return $null
    }

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

# Validate legacy client-secret fallback inputs when a secret is supplied.
if ($ClientSecret -and (-not $TenantId -or -not $ClientId)) {
    Write-Error "Client-secret fallback requires TenantId and ClientId. Production automation should use managed identity."
    exit 1
}

# Get tokens for Office 365 Management API and Dataverse
Write-Host "Authenticating..." -ForegroundColor Gray

try {
    $managementToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$ManagementApiEndpoint/.default" -ManagedIdentityClientId $ManagedIdentityClientId
    Write-Host "  Office 365 Management API: authenticated" -ForegroundColor Green
}
catch {
    Write-Error "Failed to authenticate to Office 365 Management API: $($_.Exception.Message)"
    exit 1
}

try {
    $dataverseToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default" -ManagedIdentityClientId $ManagedIdentityClientId
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
$resources = Get-AccessedResources -Events $events

Write-Host "  Connectors: $($resources.Connectors.Count) unique ($($resources.Connectors -join ', '))"
Write-Host "  SharePoint Sites: $($resources.Sites.Count) unique"
Write-Host "  Dataverse Tables: $($resources.Tables.Count) unique ($($resources.Tables -join ', '))"
Write-Host "  External APIs: $($resources.APIs.Count) unique"

# Build scope definition
Write-Host ""
Write-Host "Building scope definition..." -ForegroundColor Gray
$scopeDefinition = Get-ScopeFromHistory -Resources $resources -AgentId $AgentId -EnvironmentId $EnvironmentId -OwnerId $OwnerId -Zone $Zone

if ($events.Count -eq 0) {
    Write-Host "  No audit events found - creating empty baseline" -ForegroundColor Yellow
    Write-Host "  (New agent will be monitored for any data access)" -ForegroundColor Yellow
}
else {
    Write-Host "  Scope built from $($events.Count) events" -ForegroundColor Green
}

# Check for existing active baseline (prevent duplicate scope records)
Write-Host ""
Write-Host "Checking for existing active baseline..." -ForegroundColor Gray

$existingCheckHeaders = @{
    "Authorization"    = "Bearer $dataverseToken"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}
$sanitizedAgentId = $AgentId -replace "'", "''"
$sanitizedEnvironmentId = $EnvironmentId -replace "'", "''"
$activeStatus = if ($env:fsi_SDM_ActiveScopeStatus) { $env:fsi_SDM_ActiveScopeStatus } else { "10002" }
$filterQuery = "`$filter=fsi_agentid eq '$sanitizedAgentId' and fsi_environmentid eq '$sanitizedEnvironmentId' and fsi_status eq $activeStatus&`$select=fsi_agentscopeid,fsi_name&`$top=1"
$existingUri = "$Environment/api/data/v9.2/fsi_agentscopes?$filterQuery"

try {
    $existingScopes = Invoke-RestMethod -Uri $existingUri -Headers $existingCheckHeaders -Method Get
    if ($existingScopes.value -and $existingScopes.value.Count -gt 0) {
        $existingId = $existingScopes.value[0].fsi_agentscopeid
        Write-Error "An active baseline already exists for agent '$AgentId' in environment '$EnvironmentId' (Scope ID: $existingId). Deactivate or archive the existing baseline before creating a new one."
        exit 1
    }
    Write-Host "  No existing active baseline found" -ForegroundColor Green
}
catch {
    # Fail closed: if we cannot determine whether a duplicate baseline exists,
    # do NOT proceed -- silently creating a duplicate would corrupt the active scope
    # set and the scanner would non-deterministically pick one (Goldeneye M1).
    # Force the operator to retry once Dataverse access is restored, or pass
    # -SkipDuplicateCheck if intentional override is required.
    if ($SkipDuplicateCheck) {
        Write-Warning "Could not check for existing baselines: $($_.Exception.Message). -SkipDuplicateCheck specified; proceeding with creation."
    }
    else {
        Write-Error "Could not check for existing baselines (fail-closed): $($_.Exception.Message). Re-run when Dataverse access is healthy, or pass -SkipDuplicateCheck to override."
        exit 1
    }
}

# Create scope in Dataverse
Write-Host ""
Write-Host "Creating scope definition in Dataverse..." -ForegroundColor Gray

try {
    $result = New-ScopeDefinition -Environment $Environment -Token $dataverseToken -Scope $scopeDefinition
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
