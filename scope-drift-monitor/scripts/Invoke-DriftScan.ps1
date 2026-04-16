#Requires -Version 7.0

<#
.SYNOPSIS
    Performs manual drift detection scan for AI agents.

.DESCRIPTION
    Queries the Unified Audit Log for CopilotInteraction events and compares
    accessed resources against declared agent scopes. Creates violation records
    for any out-of-scope access.

.PARAMETER Environment
    The Dataverse environment URL (e.g., https://contoso.crm.dynamics.com).

.PARAMETER AgentId
    Optional. The Copilot Studio agent ID to scan. If omitted, scans all active agents.

.PARAMETER Minutes
    Lookback window in minutes. Default: 15.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Defaults to AZURE_TENANT_ID environment variable.

.PARAMETER ClientId
    Microsoft Entra ID application client ID. Defaults to AZURE_CLIENT_ID environment variable.

.PARAMETER ClientSecret
    Microsoft Entra ID application client secret. Defaults to AZURE_CLIENT_SECRET environment variable.

.EXAMPLE
    .\Invoke-DriftScan.ps1 -Environment "https://contoso.crm.dynamics.com"
    Scans all active agents for the last 15 minutes.

.EXAMPLE
    .\Invoke-DriftScan.ps1 -Environment "https://contoso.crm.dynamics.com" -AgentId "12345..." -Minutes 60
    Scans specific agent for the last 60 minutes.

.NOTES
    Requires:
    - Microsoft Entra ID application with Office 365 Management APIs permissions (ActivityFeed.Read)
    - Microsoft Entra ID application with Dataverse permissions
    - Microsoft 365 E5 or E5 Compliance license for CopilotInteraction events
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$AgentId,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1440)]
    [int]$Minutes = 15,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [securestring]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidateSet("https://manage.office.com", "https://manage.office365.us", "https://manage.office.eaglex.ic.gov", "https://manage.protection.outlook.com")]
    [string]$ManagementApiEndpoint = "https://manage.office.com"
)

$ErrorActionPreference = "Stop"

# Convert environment variable to SecureString if parameter not provided
if (-not $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    $ClientSecret = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
}

# Structured audit logging
function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$CorrelationId = $script:CorrelationId
    )
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ" -AsUTC
    Write-Host "[$timestamp] [$Level] [$CorrelationId] $Message"
}
$script:CorrelationId = [guid]::NewGuid().ToString("N").Substring(0,8)

# Align with Customizations.xml picklist values
$ViolationType = @{
    Connector      = 10001
    SharePointSite = 10002
    DataverseTable = 10003
    ExternalAPI    = 10004
    ExpiredScope   = 10005
    NoBaseline     = 10006
}

#region Helper Functions

function Get-AccessToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [securestring]$ClientSecret,

        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    $loginEndpoint = switch -Wildcard ($Scope) {
        "*office365.us*"           { "https://login.microsoftonline.us" }
        "*eaglex.ic.gov*"          { "https://login.microsoftonline.us" }
        "*protection.outlook.com*" { "https://login.microsoftonline.us" }
        default                    { "https://login.microsoftonline.com" }
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

function Get-ActiveScopes {
    <#
    .SYNOPSIS
        Retrieves active agent scopes from Dataverse.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $false)]
        [string]$AgentId
    )

    $headers = @{
        "Authorization"    = "Bearer $Token"
        "Content-Type"     = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        "Prefer"           = "odata.include-annotations=*"
    }

    # Query for Active status using configurable environment variable with fallback
    $activeStatusValue = if ($env:fsi_SDM_ActiveScopeStatus) { $env:fsi_SDM_ActiveScopeStatus } else { "10002" }
    $filter = "fsi_status eq $activeStatusValue"
    if ($AgentId) {
        $sanitizedAgentId = $AgentId -replace "'", "''"
        $filter = "$filter and fsi_agentid eq '$sanitizedAgentId'"
    }

    $uri = "$Environment/api/data/v9.2/fsi_agentscopes?`$filter=$filter"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        return $response.value
    }
    catch {
        throw "Failed to query agent scopes from Dataverse: $($_.Exception.Message)"
    }
}

function Get-AuditEvents {
    <#
    .SYNOPSIS
        Queries Office 365 Management API for recent CopilotInteraction events.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [int]$Minutes,

        [Parameter(Mandatory = $false)]
        [string]$ApiEndpoint = "https://manage.office.com"
    )

    $events = @()
    $startTime = (Get-Date).AddMinutes(-$Minutes).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    $endTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    # Get content blobs for the time period
    $contentUri = "$ApiEndpoint/api/v1.0/$TenantId/activity/feed/subscriptions/content?contentType=Audit.General&startTime=$startTime&endTime=$endTime"

    try {
        $contentBlobs = @()
        $nextPageUri = $contentUri

        # Handle pagination
        while ($nextPageUri) {
            # Validate pagination URL host
            $escapedEndpoint = [regex]::Escape($ApiEndpoint)
            if ($nextPageUri -notmatch "^$escapedEndpoint/") {
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

        # Fetch each content blob
        foreach ($blob in $contentBlobs) {
            try {
                # Validate content blob URI host
                $escapedBlobEndpoint = [regex]::Escape($ApiEndpoint)
                if ($blob.contentUri -notmatch "^$escapedBlobEndpoint/") {
                    Write-Warning "Skipping untrusted content URI: $($blob.contentUri)"
                    continue
                }
                $blobEvents = Invoke-RestMethod -Uri $blob.contentUri -Headers $headers -Method Get

                # Filter for CopilotInteraction events (RecordType 261)
                $copilotEvents = $blobEvents | Where-Object { $_.RecordType -eq 261 }
                $events += $copilotEvents
            }
            catch {
                Write-Warning "Could not fetch content blob: $($_.Exception.Message)"
            }
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 403) {
            Write-Warning "Access denied to Office 365 Management API. Ensure E5/E5 Compliance license and ActivityFeed.Read permission."
        }
        else {
            Write-Warning "Could not query audit content: $($_.Exception.Message)"
        }
    }

    return $events
}

function Compare-ScopeVsActual {
    <#
    .SYNOPSIS
        Compares an event's accessed resources against the agent's allowed scope.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Event,

        [Parameter(Mandatory = $false)]
        $Scope
    )

    $violations = @()
    $eventData = $Event.EventData

    # If no scope found, all access is a violation
    if (-not $Scope) {
        $violations += @{
            Type        = "No Baseline Defined"
            Resource    = "All accessed resources"
            Severity    = 10002  # High
            Details     = "Agent has no baseline scope defined. All access flagged for review."
        }
        return $violations
    }

    # Parse allowed resources from scope
    $allowedConnectors = @()
    $allowedSites = @()
    $allowedTables = @()
    $allowedApis = @()

    try {
        if ($Scope.fsi_allowedconnectors -and $Scope.fsi_allowedconnectors -ne "[]") {
            $allowedConnectors = $Scope.fsi_allowedconnectors | ConvertFrom-Json
        }
        if ($Scope.fsi_allowedsites -and $Scope.fsi_allowedsites -ne "[]") {
            $allowedSites = $Scope.fsi_allowedsites | ConvertFrom-Json
        }
        if ($Scope.fsi_allowedtables -and $Scope.fsi_allowedtables -ne "[]") {
            $allowedTables = $Scope.fsi_allowedtables | ConvertFrom-Json
        }
        if ($Scope.fsi_allowedapis -and $Scope.fsi_allowedapis -ne "[]") {
            $allowedApis = $Scope.fsi_allowedapis | ConvertFrom-Json
        }
    }
    catch {
        Write-Warning "Could not parse allowed resources from scope: $($_.Exception.Message)"
    }

    # Check connectors from AISystemPlugin
    if ($eventData.AISystemPlugin) {
        foreach ($plugin in $eventData.AISystemPlugin) {
            if ($plugin.Name -and $plugin.Enabled -eq $true) {
                $connectorName = $plugin.Name
                if ($connectorName -notin $allowedConnectors) {
                    $violations += @{
                        Type        = "Unauthorized Connector"
                        Resource    = $connectorName
                        Severity    = 10002  # High
                        Details     = "Connector '$connectorName' not in allowed list"
                    }
                }
            }
        }
    }

    # Check SharePoint sites from Contexts and AccessedResources
    $accessedSites = @()

    if ($eventData.Contexts) {
        foreach ($context in $eventData.Contexts) {
            if ($context.Id -match "(https://[^/]+\.sharepoint\.com/(?:sites|teams)/[^/]+)") {
                $siteUrl = $Matches[1]
                if ($siteUrl -notin $accessedSites) {
                    $accessedSites += $siteUrl
                }
            }
        }
    }

    if ($eventData.AccessedResources) {
        foreach ($resource in $eventData.AccessedResources) {
            if ($resource.SiteUrl -and $resource.SiteUrl -notin $accessedSites) {
                $accessedSites += $resource.SiteUrl
            }
        }
    }

    foreach ($site in $accessedSites) {
        if ($site -notin $allowedSites) {
            $violations += @{
                Type        = "Unauthorized SharePoint Site"
                Resource    = $site
                Severity    = 10003  # Medium
                Details     = "SharePoint site '$site' not in allowed list"
            }
        }
    }

    # Check Dataverse tables and external APIs from AccessedResources
    if ($eventData.AccessedResources) {
        foreach ($resource in $eventData.AccessedResources) {
            # Connectors from AccessedResources
            if ($resource.Type -eq "Connector") {
                $connectorName = $resource.Name
                if ($connectorName -and $connectorName -notin $allowedConnectors) {
                    $violations += @{
                        Type        = "Unauthorized Connector"
                        Resource    = $connectorName
                        Severity    = 10002  # High
                        Details     = "Connector '$connectorName' not in allowed list"
                    }
                }
            }

            # Dataverse tables
            if ($resource.Type -eq "DataverseTable" -or $resource.Type -eq "Table") {
                if ($resource.Name -notin $allowedTables) {
                    $violations += @{
                        Type        = "Unauthorized Dataverse Table"
                        Resource    = $resource.Name
                        Severity    = 10003  # Medium
                        Details     = "Dataverse table '$($resource.Name)' not in allowed list"
                    }
                }
            }

            # External APIs
            if ($resource.Type -eq "ExternalAPI" -or
                ($resource.Url -match "^https?://" -and $resource.Url -notmatch "(sharepoint|microsoft|office)\.com")) {
                if ($resource.Url -notin $allowedApis) {
                    $violations += @{
                        Type        = "Unauthorized External API"
                        Resource    = $resource.Url
                        Severity    = 10002  # High
                        Details     = "External API '$($resource.Url)' not in allowed list"
                    }
                }
            }
        }
    }

    return $violations
}

function Get-SeverityLabel {
    param([int]$Severity)

    switch ($Severity) {
        10001 { return "Critical" }
        10002 { return "High" }
        10003 { return "Medium" }
        10004 { return "Low" }
        default { return "Unknown" }
    }
}

function Get-ViolationTypeCode {
    param([string]$TypeName)

    switch ($TypeName) {
        "No Baseline Defined"          { return $ViolationType.NoBaseline }
        "Unauthorized Connector"       { return $ViolationType.Connector }
        "Unauthorized SharePoint Site" { return $ViolationType.SharePointSite }
        "Unauthorized Dataverse Table" { return $ViolationType.DataverseTable }
        "Unauthorized External API"    { return $ViolationType.ExternalAPI }
        default                        { return 0 }
    }
}

function New-ViolationRecord {
    <#
    .SYNOPSIS
        Creates a violation record in Dataverse.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [hashtable]$Violation,

        [Parameter(Mandatory = $false)]
        [string]$ScopeId,

        [Parameter(Mandatory = $false)]
        [string]$AuditRecordId,

        [Parameter(Mandatory = $false)]
        [string]$UserId
    )

    $headers = @{
        "Authorization"    = "Bearer $Token"
        "Content-Type"     = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
    }

    # Deduplication: skip if a violation for this audit record, resource, and type already exists
    if ($AuditRecordId) {
        $sanitizedAuditId = $AuditRecordId -replace "'", "''"
        $sanitizedResource = ($Violation.Resource -replace "'", "''")
        $violationTypeCode = Get-ViolationTypeCode -TypeName $Violation.Type
        $checkUri = "$Environment/api/data/v9.2/fsi_scopeviolations?`$filter=fsi_auditrecordid eq '$sanitizedAuditId' and fsi_resourcename eq '$sanitizedResource' and fsi_violationtype eq $violationTypeCode&`$select=fsi_scopeviolationid&`$top=1"
        try {
            $existing = Invoke-RestMethod -Uri $checkUri -Headers $headers -Method Get
            if ($existing.value.Count -gt 0) {
                Write-AuditLog "Skipping duplicate violation for audit record $AuditRecordId" -Level "DEBUG"
                return $null
            }
        }
        catch {
            Write-Warning "Could not check for existing violation: $($_.Exception.Message)"
        }
    }

    $violationRecord = @{
        fsi_name          = & { $n = "$($Violation.Type) - $($Violation.Resource)"; if ($n.Length -gt 200) { $n.Substring(0, 200) } else { $n } }
        fsi_violationtype = Get-ViolationTypeCode -TypeName $Violation.Type
        fsi_resourcename  = $Violation.Resource
        fsi_resourceurl   = if ($Violation.Resource -match "^https?://") { $Violation.Resource } else { $null }
        fsi_severity      = $Violation.Severity
        fsi_status        = 10001  # Open
        fsi_detectedon    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        fsi_accessdetails = $Violation.Details
    }

    # Add scope reference if available
    if ($ScopeId) {
        $violationRecord["fsi_agentscopeid@odata.bind"] = "/fsi_agentscopes($ScopeId)"
    }

    # Add audit record ID if available
    if ($AuditRecordId) {
        $violationRecord.fsi_auditrecordid = $AuditRecordId
    }

    $uri = "$Environment/api/data/v9.2/fsi_scopeviolations"
    $body = $violationRecord | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body
        return $response
    }
    catch {
        Write-Warning "Could not create violation record: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Main Script

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Scope Drift Detection Scanner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-AuditLog "Drift scan starting — Environment=$Environment AgentFilter=$(if ($AgentId) { $AgentId } else { 'All' }) Lookback=${Minutes}m"

Write-Host "Environment: $Environment"
Write-Host "Agent Filter: $(if ($AgentId) { $AgentId } else { 'All active agents' })"
Write-Host "Lookback: $Minutes minutes"
Write-Host ""

# Validate credentials
if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Error "Missing credentials. Set environment variables: AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET"
    exit 1
}

# Authenticate
Write-Host "Authenticating..." -ForegroundColor Gray

try {
    $managementToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$ManagementApiEndpoint/.default"
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

# Get active scopes from Dataverse
Write-Host ""
Write-Host "Loading active agent scopes..." -ForegroundColor Gray

try {
    $scopes = Get-ActiveScopes -Environment $Environment -Token $dataverseToken -AgentId $AgentId
    Write-Host "  Found $($scopes.Count) active scope(s)"
}
catch {
    Write-Error "Failed to load agent scopes: $($_.Exception.Message)"
    exit 1
}

# Build scope lookup by agent ID and environment ID (composite key)
$scopeLookup = @{}
foreach ($scope in $scopes) {
    $envId = if ($scope.fsi_environmentid) { $scope.fsi_environmentid } else { "" }
    $scopeLookup["$($scope.fsi_agentid)|$envId"] = $scope
}

# Get audit events
Write-Host ""
Write-Host "Querying audit events from last $Minutes minutes..." -ForegroundColor Gray
$events = Get-AuditEvents -Token $managementToken -TenantId $TenantId -Minutes $Minutes -ApiEndpoint $ManagementApiEndpoint
Write-Host "  Found $($events.Count) CopilotInteraction event(s)"

# Process events and detect violations
Write-Host ""
Write-Host "Analyzing events for scope violations..." -ForegroundColor Gray

$totalViolations = 0
$violationResults = @()
$agentsScanned = @{}

foreach ($event in $events) {
    # Try to identify agent from event
    $eventAgentId = $null

    # Check EventData for agent identification
    if ($event.EventData.AgentId) {
        $eventAgentId = $event.EventData.AgentId
    }
    elseif ($event.EventData.Contexts -and $event.EventData.Contexts[0].Id) {
        # Use first context as agent identifier if explicit ID not present
        $eventAgentId = $event.EventData.Contexts[0].Id
    }

    # Skip if we're filtering for a specific agent and this isn't it
    if ($AgentId -and $eventAgentId -ne $AgentId) {
        continue
    }

    # Track scanned agents
    if ($eventAgentId) {
        $agentsScanned[$eventAgentId] = $true
    }

    # Get scope for this agent; null EnvironmentId acts as wildcard (matches any scope for this agent)
    $eventEnvId = if ($event.EventData.EnvironmentId) { $event.EventData.EnvironmentId } else { $null }
    $scope = $null
    if ($eventAgentId) {
        if ($eventEnvId) {
            $scope = $scopeLookup["$eventAgentId|$eventEnvId"]
        }
        if (-not $scope) {
            # Wildcard: match first scope for this agent (consistent with flow's or(equals(EnvironmentId, null), ...) logic)
            $scope = $scopeLookup.GetEnumerator() | Where-Object { $_.Key.StartsWith("$eventAgentId|") } | Select-Object -First 1 -ExpandProperty Value
        }
    }

    # Skip events with no identifiable agent — avoids false "No Baseline" violations
    if (-not $eventAgentId) {
        continue
    }

    # Compare scope vs actual access
    $violations = Compare-ScopeVsActual -Event $event -Scope $scope

    # Create violation records
    foreach ($violation in $violations) {
        $scopeId = if ($scope) { $scope.fsi_agentscopeid } else { $null }
        $auditRecordId = $event.Id

        $result = New-ViolationRecord `
            -Environment $Environment `
            -Token $dataverseToken `
            -Violation $violation `
            -ScopeId $scopeId `
            -AuditRecordId $auditRecordId `
            -UserId $event.UserId

        if ($result) {
            $totalViolations++
            $violationResults += @{
                Agent    = if ($eventAgentId) { $eventAgentId } else { "Unknown" }
                Type     = $violation.Type
                Resource = $violation.Resource
                Severity = Get-SeverityLabel -Severity $violation.Severity
            }
            Write-AuditLog "Violation detected — Agent=$(if ($eventAgentId) { $eventAgentId } else { 'Unknown' }) Type=$($violation.Type) Resource=$($violation.Resource) Severity=$(Get-SeverityLabel -Severity $violation.Severity)" -Level "WARN"
        }
    }
}

# Display summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Scan Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:"
Write-Host "  - Events analyzed: $($events.Count)"
Write-Host "  - Agents scanned: $($agentsScanned.Count)"
Write-Host "  - Violations found: $totalViolations"
Write-Host ""

if ($violationResults.Count -gt 0) {
    Write-Host "Violations:" -ForegroundColor Yellow
    Write-Host ""

    foreach ($v in $violationResults) {
        $severityColor = switch ($v.Severity) {
            "Critical" { "Red" }
            "High" { "DarkRed" }
            "Medium" { "Yellow" }
            "Low" { "Gray" }
            default { "White" }
        }

        Write-Host "  [$($v.Severity)] " -ForegroundColor $severityColor -NoNewline
        Write-Host "$($v.Type): $($v.Resource)"
    }
    Write-Host ""
}
else {
    Write-Host "No violations detected." -ForegroundColor Green
    Write-Host ""
}

# Return violation objects for pipeline use
$output = [PSCustomObject]@{
    EventsAnalyzed    = $events.Count
    AgentsScanned     = $agentsScanned.Count
    ViolationsFound   = $totalViolations
    Violations        = $violationResults
    ScanTime          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

Write-AuditLog "Drift scan complete — Events=$($events.Count) Agents=$($agentsScanned.Count) Violations=$totalViolations"

Write-Output $output

# Exit 0 even if violations found (success = scan completed)
exit 0

#endregion
