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
    Legacy dev-only Microsoft Entra ID application client secret. Defaults to AZURE_CLIENT_SECRET environment variable. Production automation should use managed identity.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID. Defaults to AZURE_MANAGED_IDENTITY_CLIENT_ID. If omitted, system-assigned managed identity is used when available.

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
    [string]$ManagementApiEndpoint = "https://manage.office.com",

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityClientId = $env:AZURE_MANAGED_IDENTITY_CLIENT_ID
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
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
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
                    $script:auditFetchErrors++
                    continue
                }
                $blobEvents = Invoke-RestMethod -Uri $blob.contentUri -Headers $headers -Method Get

                # Filter for CopilotInteraction events (RecordType 261)
                $copilotEvents = $blobEvents | Where-Object { $_.RecordType -eq 261 }
                $events += $copilotEvents
            }
            catch {
                Write-Warning "Could not fetch content blob: $($_.Exception.Message)"
                $script:auditFetchErrors++
            }
        }
    }
    catch {
        $script:auditFetchErrors++
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
    $eventData = Get-CopilotEventData -Event $Event

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
        foreach ($plugin in @($eventData.AISystemPlugin)) {
            if ($plugin.Name) {
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
        foreach ($context in @($eventData.Contexts)) {
            if ($context.Id -match "(https://[^/]+\.sharepoint\.com/(?:sites|teams)/[^/]+)") {
                $siteUrl = $Matches[1]
                if ($siteUrl -notin $accessedSites) {
                    $accessedSites += $siteUrl
                }
            }
        }
    }

    if ($eventData.AccessedResources) {
        foreach ($resource in @($eventData.AccessedResources)) {
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
        foreach ($resource in @($eventData.AccessedResources)) {
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
            $resourceUri = Get-ResourceUri -Resource $resource
            if ($resource.Type -eq "ExternalAPI" -or
                ($resourceUri -match "^https?://" -and $resourceUri -notmatch "(sharepoint|microsoft|office)\.com")) {
                if ($resourceUri -and $resourceUri -notin $allowedApis) {
                    $violations += @{
                        Type        = "Unauthorized External API"
                        Resource    = $resourceUri
                        Severity    = 10002  # High
                        Details     = "External API '$resourceUri' not in allowed list"
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

function Get-MatchingScope {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Scopes,

        [Parameter(Mandatory = $false)]
        [string]$EventAgentId,

        [Parameter(Mandatory = $false)]
        [string]$EventEnvironmentId
    )

    foreach ($scope in @($Scopes)) {
        $scopeEnvironmentId = if ($scope.fsi_environmentid) { [string]$scope.fsi_environmentid } else { "" }
        $environmentMatches = [string]::IsNullOrWhiteSpace($EventEnvironmentId) -or
            [string]::IsNullOrWhiteSpace($scopeEnvironmentId) -or
            $scopeEnvironmentId.Equals($EventEnvironmentId, [System.StringComparison]::OrdinalIgnoreCase)

        if ($environmentMatches -and (Test-AgentIdMatch -EventAgentId $EventAgentId -ExpectedAgentId $scope.fsi_agentid)) {
            return $scope
        }
    }

    return $null
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

Write-AuditLog "Drift scan starting -- Environment=$Environment AgentFilter=$(if ($AgentId) { $AgentId } else { 'All' }) Lookback=${Minutes}m"

Write-Host "Environment: $Environment"
Write-Host "Agent Filter: $(if ($AgentId) { $AgentId } else { 'All active agents' })"
Write-Host "Lookback: $Minutes minutes"
Write-Host ""

# Validate legacy client-secret fallback inputs when a secret is supplied.
if ($ClientSecret -and (-not $TenantId -or -not $ClientId)) {
    Write-Error "Client-secret fallback requires TenantId and ClientId. Production automation should use managed identity."
    exit 1
}

# Authenticate
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
$script:auditFetchErrors = 0
$events = Get-AuditEvents -Token $managementToken -TenantId $TenantId -Minutes $Minutes -ApiEndpoint $ManagementApiEndpoint
Write-Host "  Found $($events.Count) CopilotInteraction event(s)"
if ($script:auditFetchErrors -gt 0) {
    Write-Warning "Audit-content fetch encountered $($script:auditFetchErrors) error(s); results may be incomplete."
}

# Process events and detect violations
Write-Host ""
Write-Host "Analyzing events for scope violations..." -ForegroundColor Gray

$totalViolations = 0
$violationResults = @()
$agentsScanned = @{}

foreach ($event in $events) {
    $eventData = Get-CopilotEventData -Event $event
    $eventAgentId = Get-CopilotAgentId -Event $event

    # Skip if we're filtering for a specific agent and this isn't it.
    if ($AgentId -and -not (Test-AgentIdMatch -EventAgentId $eventAgentId -ExpectedAgentId $AgentId)) {
        continue
    }

    # Skip events with no identifiable agent -- avoids false "No Baseline" violations.
    if (-not $eventAgentId) {
        continue
    }

    # Track scanned agents
    $agentsScanned[$eventAgentId] = $true

    # Get scope for this agent; blank EnvironmentId acts as wildcard.
    $eventEnvId = if ($event.EnvironmentId) { $event.EnvironmentId } elseif ($eventData.EnvironmentId) { $eventData.EnvironmentId } else { $null }
    $scope = Get-MatchingScope -Scopes $scopes -EventAgentId $eventAgentId -EventEnvironmentId $eventEnvId

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
            Write-AuditLog "Violation detected -- Agent=$(if ($eventAgentId) { $eventAgentId } else { 'Unknown' }) Type=$($violation.Type) Resource=$($violation.Resource) Severity=$(Get-SeverityLabel -Severity $violation.Severity)" -Level "WARN"
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

Write-AuditLog "Drift scan complete -- Events=$($events.Count) Agents=$($agentsScanned.Count) Violations=$totalViolations FetchErrors=$($script:auditFetchErrors)"

Write-Output $output

# Exit code reflects scan integrity:
#   0 = scan completed cleanly
#   2 = scan completed but audit-content fetches reported errors and no events arrived
#       (callers should treat this as inconclusive, not as "no violations")
if ($script:auditFetchErrors -gt 0 -and $events.Count -eq 0) {
    Write-Warning "Drift scan inconclusive: $($script:auditFetchErrors) audit-fetch error(s) and zero events. Exiting with code 2."
    exit 2
}
exit 0

#endregion
