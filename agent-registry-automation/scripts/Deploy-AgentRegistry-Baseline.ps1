#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '5.3.4' }

<#
.SYNOPSIS
    Exports baseline agent inventory from Power Platform to Dataverse.

.DESCRIPTION
    Enumerates Power Platform environments via the Business Application
    Platform (BAP) admin API, then discovers Copilot Studio agents by
    querying each environment's Dataverse `bot` table (entity set `bots`).
    Creates initial agent inventory records in the registry's
    fsi_agentinventory Dataverse table. Uses Managed Identity
    authentication exclusively — no client secrets.

    Authoritative sources for the discovery surface:
    - Environment enumeration (BAP admin API):
      https://learn.microsoft.com/rest/api/power-platform/ (List environments)
      GET https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01
    - Copilot Studio agents are stored in the Dataverse `bot` table:
      https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/bot
      EntitySetName `bots`, PrimaryIdAttribute `botid`, PrimaryNameAttribute `name`.

    This script is typically run once during initial deployment to
    establish the baseline agent inventory. Subsequent updates are
    handled by the Discover-UnregisteredAgents-Daily flow.

.PARAMETER DataverseUrl
    Target *registry* Dataverse environment URL where the fsi_* tables live
    (e.g., https://example.crm.dynamics.com). Each scanned environment's own
    Dataverse URL is resolved from the BAP environment metadata.

.PARAMETER BapApiUrl
    Business Application Platform admin API base URL. Defaults to
    https://api.bap.microsoft.com.

.PARAMETER ExportPath
    Optional path to export baseline inventory as JSON file.
    Supports examiner evidence requirements (FINRA 4511, SEC 17a-3).

.PARAMETER Zone
    Default zone classification for discovered agents.
    Valid values: 1, 2, 3. Default: 1.

.PARAMETER WhatIf
    Shows what would be written to Dataverse without making changes.

.EXAMPLE
    .\Deploy-AgentRegistry-Baseline.ps1 `
        -DataverseUrl "https://example.crm.dynamics.com" `
        -ExportPath ".\baseline-inventory-$(Get-Date -Format yyyyMMdd).json"

.EXAMPLE
    .\Deploy-AgentRegistry-Baseline.ps1 `
        -DataverseUrl "https://example.crm.dynamics.com" `
        -Zone 2 `
        -WhatIf

.NOTES
    Requires:
    - Azure Automation with System-Assigned Managed Identity
    - Managed Identity assigned Power Platform Administrator role
      (for BAP admin environment enumeration)
    - Managed Identity granted a Dataverse security role with read access to
      the `bot` table in EACH environment to be scanned
    - Managed Identity assigned System Administrator in the *registry*
      Dataverse environment (to write fsi_* records)
    - Az.Accounts PowerShell module
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$BapApiUrl = "https://api.bap.microsoft.com",

    [Parameter()]
    [string]$ExportPath,

    [Parameter()]
    [ValidateRange(1, 3)]
    [int]$Zone = 1
)

$ErrorActionPreference = "Stop"

# --- Constants -------------------------------------------------------------------

$script:DataverseApiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
$script:CorrelationId = [guid]::NewGuid().ToString("N").Substring(0, 8)
$script:MaxRetries = 3

$script:ZoneOptionSet = @{
    1 = 100000001  # Zone 1 - Personal
    2 = 100000002  # Zone 2 - Team
    3 = 100000003  # Zone 3 - Enterprise
}

$script:RegistrationStatusUnregistered = 100000000

# fsi_ara_publishedstatus option set values (from create_dataverse_schema.py)
$script:PublishedStatusMap = @{
    'Published'   = 100000000
    'Draft'       = 100000001
    'Quarantined' = 100000002
    'Disabled'    = 100000003
}

# --- Helper Functions ------------------------------------------------------------

function Write-AuditLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $color = switch ($Level) {
        "INFO"  { "Gray" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
    }
    Write-Host "[$timestamp] [$Level] [$script:CorrelationId] $Message" -ForegroundColor $color
}

function Get-ManagedIdentityToken {
    <#
    .SYNOPSIS
        Acquires an access token using the system-assigned Managed Identity.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ResourceUrl
    )

    $normalizedUrl = $ResourceUrl.TrimEnd('/')
    $tokenResult = Get-AzAccessToken -ResourceUrl $normalizedUrl -ErrorAction Stop

    # Az.Accounts >= 3.0 returns SecureString; earlier versions return plain string
    if ($tokenResult.Token -is [System.Security.SecureString]) {
        return $tokenResult.Token | ConvertFrom-SecureString -AsPlainText
    }
    return $tokenResult.Token
}

function Invoke-ApiRequest {
    <#
    .SYNOPSIS
        Invokes a REST API request with retry logic for 429 and 5xx errors.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Token,

        [ValidateSet("GET", "POST", "PATCH")]
        [string]$Method = "GET",

        [hashtable]$Body,

        [int]$MaxRetries = $script:MaxRetries
    )

    $headers = @{
        "Authorization"    = "Bearer $Token"
        "Content-Type"     = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        "Accept"           = "application/json"
    }

    $requestParams = @{
        Uri     = $Uri
        Headers = $headers
        Method  = $Method
    }

    if ($Body -and $Method -ne "GET") {
        $requestParams["Body"] = $Body | ConvertTo-Json -Depth 10
    }

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            return Invoke-RestMethod @requestParams
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if ($statusCode -eq 429 -and $attempt -lt $MaxRetries) {
                $retryAfter = 5 * $attempt
                Write-AuditLog "Rate limited (429). Retrying in ${retryAfter}s (attempt $attempt/$MaxRetries)..." -Level WARN
                Start-Sleep -Seconds $retryAfter
            }
            elseif ($statusCode -ge 500 -and $attempt -lt $MaxRetries) {
                $retryAfter = 3 * $attempt
                Write-AuditLog "Server error ($statusCode). Retrying in ${retryAfter}s (attempt $attempt/$MaxRetries)..." -Level WARN
                Start-Sleep -Seconds $retryAfter
            }
            else {
                throw
            }
        }
    }
}

function Get-PagedApiValues {
    <#
    .SYNOPSIS
        Retrieves all pages from an API response that returns value plus a nextLink.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri

    while ($nextUri) {
        $response = Invoke-ApiRequest -Uri $nextUri -Token $Token -Method GET
        if ($response.value) {
            $items.AddRange(@($response.value))
        }

        $nextUri = $response.'@odata.nextLink'
        if (-not $nextUri -and $response.nextLink) {
            $nextUri = $response.nextLink
        }
    }

    return $items
}

function Get-PowerPlatformEnvironments {
    <#
    .SYNOPSIS
        Lists all Power Platform environments via the BAP admin API.

    .DESCRIPTION
        Uses the documented Business Application Platform admin route:
        GET https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01
        Each returned environment exposes the Dataverse organization URL at
        properties.linkedEnvironmentMetadata.instanceUrl, which is used to
        query that environment's `bot` table for agent discovery.
        Ref: https://learn.microsoft.com/rest/api/power-platform/ (List environments)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ApiBaseUrl,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $uri = "$($ApiBaseUrl.TrimEnd('/'))/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01"
    Write-AuditLog "Querying Power Platform environments (BAP admin API)..."

    $environments = Get-PagedApiValues -Uri $uri -Token $Token

    Write-AuditLog "Found $($environments.Count) environment(s)"
    return $environments
}

function Get-EnvironmentBots {
    <#
    .SYNOPSIS
        Lists Copilot Studio agents in an environment via its Dataverse `bot` table.

    .DESCRIPTION
        Copilot Studio agents are stored as rows in the Dataverse `bot` table
        (entity set `bots`, PrimaryIdAttribute `botid`, PrimaryNameAttribute
        `name`). There is no Power Platform "Bots API" route for enumeration;
        the authoritative inventory source is the per-environment Dataverse
        Web API.
        Ref: https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/bot

        $InstanceUrl is the environment's Dataverse organization URL, taken
        from the BAP environment metadata. A separate Dataverse token (audience
        = $InstanceUrl) is required because each environment is a distinct
        Dataverse resource.

        NOTE (runtime-verify): the owner expand path `owninguser` and the
        statecode→published mapping should be confirmed against the live
        `bot` table in your tenant; column availability can vary by version.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$InstanceUrl,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $select = "botid,name,schemaname,statecode,_ownerid_value"
    $expand = "owninguser(`$select=domainname,internalemailaddress)"
    $uri = "$($InstanceUrl.TrimEnd('/'))/api/data/v9.2/bots?`$select=$select&`$expand=$expand"

    try {
        return @(Get-PagedApiValues -Uri $uri -Token $Token)
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        # 401/403/404 typically means the identity has no Dataverse access in
        # this environment, or the org is not provisioned — skip gracefully.
        if ($statusCode -in @(401, 403, 404)) {
            Write-AuditLog "No bot-table access at $InstanceUrl (HTTP $statusCode) — skipping" -Level WARN
            return @()
        }
        throw
    }
}

function Write-AgentInventoryRecord {
    <#
    .SYNOPSIS
        Upserts an agent inventory record in fsi_agentinventory.
        Returns 'Created' or 'Updated' to indicate the operation performed.

    .DESCRIPTION
        Idempotent. On *create*, writes the full discovery payload.
        On *update*, only refreshes columns that should track current
        Bots-API state (display names, endpoint, last-scanned timestamp,
        published status). It DOES NOT reset workflow columns like
        fsi_registrationstatus, fsi_zone, fsi_isorphaned, or fsi_ownerupn —
        those are governed by the registration approval flow and must not
        be clobbered by a second discovery pass.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter(Mandatory)]
        [hashtable]$AgentData
    )

    $agentId = $AgentData.fsi_agentid
    $envId = $AgentData.fsi_environmentid
    $filter = "`$filter=fsi_agentid eq '$agentId' and fsi_environmentid eq '$envId'"
    $select = "`$select=fsi_agentinventoryid"
    $checkUri = "$script:DataverseApiBase/fsi_agentinventories?$filter&$select&`$top=1"

    $existing = Invoke-ApiRequest -Uri $checkUri -Token $Token -Method GET

    if ($existing.value -and $existing.value.Count -gt 0) {
        $recordId = $existing.value[0].fsi_agentinventoryid
        $updateUri = "$script:DataverseApiBase/fsi_agentinventories($recordId)"

        # Only refresh discovery-tracking fields. Preserve workflow state.
        $updatePayload = @{}
        foreach ($col in @('fsi_name','fsi_agentname','fsi_environmentname','fsi_agentendpointurl','fsi_lastscannedat','fsi_publishedstatus','fsi_rawjson')) {
            if ($AgentData.ContainsKey($col)) { $updatePayload[$col] = $AgentData[$col] }
        }
        Invoke-ApiRequest -Uri $updateUri -Token $Token -Method PATCH -Body $updatePayload | Out-Null
        return "Updated"
    }
    else {
        $createUri = "$script:DataverseApiBase/fsi_agentinventories"
        Invoke-ApiRequest -Uri $createUri -Token $Token -Method POST -Body $AgentData | Out-Null
        return "Created"
    }
}

function Write-ComplianceEvent {
    <#
    .SYNOPSIS
        Writes a compliance event to fsi_agentcomplianceevent.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter(Mandatory)]
        [string]$AgentId,

        [Parameter(Mandatory)]
        [string]$EnvironmentId,

        [Parameter(Mandatory)]
        [string]$EventType,

        [string]$Details
    )

    # fsi_ara_eventtype option set values:
    #   100000000 = Discovered, 100000001 = Registered, 100000002 = Approved,
    #   100000003 = Rejected, 100000004 = Quarantined, 100000005 = SLA_Escalated,
    #   100000006 = OrphanDetected, 100000007 = OwnerChanged,
    #   100000008 = Decommissioned, 100000009 = EntraSynced
    $eventTypeMap = @{
        "Discovered"      = 100000000
        "Registered"      = 100000001
        "Approved"        = 100000002
        "Rejected"        = 100000003
        "Quarantined"     = 100000004
        "SLA_Escalated"   = 100000005
        "OrphanDetected"  = 100000006
        "OwnerChanged"    = 100000007
        "Decommissioned"  = 100000008
        "EntraSynced"     = 100000009
    }

    $payload = @{
        fsi_name           = "Discovery - $AgentId"
        fsi_agentid        = $AgentId
        fsi_environmentid  = $EnvironmentId
        fsi_eventtype      = $eventTypeMap[$EventType]
        fsi_details        = $Details
        fsi_eventtimestamp  = (Get-Date).ToUniversalTime().ToString('o')
    }

    $uri = "$script:DataverseApiBase/fsi_agentcomplianceevents"
    Invoke-ApiRequest -Uri $uri -Token $Token -Method POST -Body $payload | Out-Null
}

# --- Main Execution --------------------------------------------------------------

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Agent Registry Baseline Deployment"     -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-AuditLog "Correlation ID: $script:CorrelationId"
Write-AuditLog "Dataverse URL:  $DataverseUrl"
Write-AuditLog "Default Zone:   $Zone"

if ($WhatIfPreference) {
    Write-AuditLog "Running in WhatIf mode — no changes will be written" -Level WARN
}

# Step 1: Authenticate with Managed Identity
Write-AuditLog "Authenticating with Managed Identity..."
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-AuditLog "Managed Identity connected"
}
catch {
    Write-AuditLog "Failed to connect Managed Identity: $($_.Exception.Message)" -Level ERROR
    Write-Error "Managed Identity authentication failed. Verify the runbook is running in Azure Automation with a system-assigned Managed Identity."
    exit 1
}

# Step 2: Acquire tokens for the BAP admin API and the registry Dataverse env
Write-AuditLog "Acquiring access tokens..."
try {
    # BAP admin API audience is the Power Apps service resource.
    # Ref: https://learn.microsoft.com/power-platform/admin/programmability-authentication
    $bapToken = Get-ManagedIdentityToken -ResourceUrl "https://service.powerapps.com/"
    Write-AuditLog "  BAP admin API:      authenticated"

    $dvToken = Get-ManagedIdentityToken -ResourceUrl $DataverseUrl
    Write-AuditLog "  Registry Dataverse: authenticated"
}
catch {
    Write-AuditLog "Token acquisition failed: $($_.Exception.Message)" -Level ERROR
    Write-Error "Failed to acquire access token. Verify the Managed Identity has appropriate role assignments."
    exit 1
}

# Step 3: List all Power Platform environments (BAP admin API)
$environments = Get-PowerPlatformEnvironments -ApiBaseUrl $BapApiUrl -Token $bapToken

if ($environments.Count -eq 0) {
    Write-AuditLog "No environments found. Verify Managed Identity has Power Platform Administrator role." -Level WARN
    exit 0
}

# Step 4: Discover bots in each environment
$allDiscoveredAgents = [System.Collections.Generic.List[hashtable]]::new()
$counters = @{
    EnvironmentsScanned = 0
    TotalAgents         = 0
    Created             = 0
    Updated             = 0
    Errors              = 0
}

# Per-environment Dataverse tokens are cached by instance URL because each
# environment is a distinct Dataverse resource (audience = its org URL).
$envTokenCache = @{}

$zoneValue = $script:ZoneOptionSet[$Zone]
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

foreach ($env in $environments) {
    $envId = $env.name  # environment GUID
    $envName = $env.properties.displayName
    # Dataverse organization URL for this environment (BAP metadata).
    $instanceUrl = $env.properties.linkedEnvironmentMetadata.instanceUrl
    $counters.EnvironmentsScanned++

    Write-AuditLog "Scanning environment: $envName ($envId)"

    if ([string]::IsNullOrWhiteSpace($instanceUrl)) {
        Write-AuditLog "  No Dataverse instance linked to $envName — skipping" -Level WARN
        continue
    }

    try {
        # Acquire (or reuse) a Dataverse token scoped to this environment.
        if (-not $envTokenCache.ContainsKey($instanceUrl)) {
            $envTokenCache[$instanceUrl] = Get-ManagedIdentityToken -ResourceUrl $instanceUrl
        }
        $envDvToken = $envTokenCache[$instanceUrl]

        $bots = Get-EnvironmentBots -InstanceUrl $instanceUrl -Token $envDvToken

        if ($bots.Count -eq 0) {
            Write-AuditLog "  No agents found in $envName"
            continue
        }

        Write-AuditLog "  Found $($bots.Count) agent(s) in $envName"

        foreach ($bot in $bots) {
            $counters.TotalAgents++
            # Dataverse `bot` table: botid is the durable GUID identifier and
            # name is the display name. Use botid for fsi_agentid so the
            # alternate key (fsi_agentid + fsi_environmentid) stays stable.
            $botId = $bot.botid
            $botName = $bot.name
            if ([string]::IsNullOrWhiteSpace($botName)) { $botName = $botId }

            $agentRecord = @{
                fsi_name               = $botName
                fsi_agentid            = $botId
                fsi_agentname          = $botName
                fsi_environmentid      = $envId
                fsi_environmentname    = $envName
                fsi_registrationstatus = $script:RegistrationStatusUnregistered
                fsi_zone               = $zoneValue
                fsi_lastscannedat      = $timestamp
                fsi_isorphaned         = $false
            }

            # Owner UPN — required column. Resolved from the expanded owning
            # user (domainname is the user's UPN/logon). If absent, populate a
            # placeholder so the create succeeds; orphan detection will flag the
            # record on the next compliance pass.
            $ownerUpn = $null
            if ($bot.owninguser) {
                $ownerUpn = $bot.owninguser.domainname
                if ([string]::IsNullOrWhiteSpace($ownerUpn)) {
                    $ownerUpn = $bot.owninguser.internalemailaddress
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($ownerUpn)) {
                $agentRecord["fsi_ownerupn"] = $ownerUpn
            } else {
                $agentRecord["fsi_ownerupn"] = "unknown@unassigned.local"
                $agentRecord["fsi_isorphaned"] = $true
            }

            # Published status — required column. The `bot` table does not
            # expose a Copilot Studio "published" lifecycle value; statecode
            # only reflects record active/inactive. Default to Draft and let
            # the registration flow govern published state from there.
            $agentRecord["fsi_publishedstatus"] = $script:PublishedStatusMap["Draft"]

            if ($PSCmdlet.ShouldProcess("$botName ($botId) in $envName", "Upsert agent inventory record")) {
                try {
                    $result = Write-AgentInventoryRecord -Token $dvToken -AgentData $agentRecord

                    if ($result -eq "Created") {
                        $counters.Created++
                        Write-AuditLog "  Created: $botName ($botId)"

                        # Log discovery event only for new agents
                        Write-ComplianceEvent -Token $dvToken `
                            -AgentId $botId `
                            -EnvironmentId $envId `
                            -EventType "Discovered" `
                            -Details "Agent discovered during baseline scan. Environment: $envName. Zone: $Zone."
                    }
                    else {
                        $counters.Updated++
                        Write-AuditLog "  Updated: $botName ($botId)"
                    }
                }
                catch {
                    $counters.Errors++
                    Write-AuditLog "  Failed to upsert $botName ($botId): $($_.Exception.Message)" -Level ERROR
                }
            }

            # Collect for export regardless of WhatIf
            $allDiscoveredAgents.Add($agentRecord)
        }
    }
    catch {
        $counters.Errors++
        Write-AuditLog "Error scanning environment $envName ($envId): $($_.Exception.Message)" -Level ERROR
    }
}

# Step 5: Export baseline inventory if path specified
if ($ExportPath) {
    Write-AuditLog "Exporting baseline inventory to $ExportPath..."

    $exportData = @{
        metadata = @{
            generatedAt   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            correlationId = $script:CorrelationId
            dataverseUrl  = $DataverseUrl
            defaultZone   = $Zone
            totalAgents   = $allDiscoveredAgents.Count
        }
        agents   = $allDiscoveredAgents
    }

    $exportJson = $exportData | ConvertTo-Json -Depth 10
    $exportJson | Out-File -FilePath $ExportPath -Encoding utf8 -Force

    # Generate SHA-256 hash for evidence integrity
    $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($exportJson)
    )
    $fileHash = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ''
    Write-AuditLog "Export SHA-256: $fileHash"
    Write-AuditLog "Baseline exported to $ExportPath"
}

# Step 6: Output summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Baseline Deployment Summary"            -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Environments scanned: $($counters.EnvironmentsScanned)"
Write-Host "  Total agents found:   $($counters.TotalAgents)"
Write-Host "  Created:              $($counters.Created)" -ForegroundColor Green
Write-Host "  Updated:              $($counters.Updated)" -ForegroundColor Yellow
Write-Host "  Errors:               $($counters.Errors)" -ForegroundColor $(if ($counters.Errors -gt 0) { "Red" } else { "Green" })
Write-Host "========================================" -ForegroundColor Cyan

if ($counters.Errors -gt 0) {
    Write-AuditLog "Completed with $($counters.Errors) error(s)" -Level WARN
    exit 1
}

Write-AuditLog "Baseline deployment completed successfully"
