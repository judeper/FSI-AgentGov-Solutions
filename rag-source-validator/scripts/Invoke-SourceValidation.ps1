<#
.SYNOPSIS
    Validates RAG knowledge source integrity.

.DESCRIPTION
    Computes content hashes for registered knowledge sources and compares
    against baseline to detect unauthorized changes.

.PARAMETER Environment
    The Dataverse environment URL.

.PARAMETER SourceId
    Specific source ID to validate (optional - validates all if not specified).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID for the legacy client-secret fallback. Defaults to the AZURE_TENANT_ID environment variable.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for the legacy client-secret fallback. Defaults to the AZURE_CLIENT_ID environment variable.

.PARAMETER ClientSecret
    Microsoft Entra ID client secret as a SecureString for legacy development-only fallback. Falls back to the AZURE_CLIENT_SECRET environment variable if not provided.

.PARAMETER UseManagedIdentity
    Use Azure managed identity authentication. This is the recommended production path for Azure Automation, Azure Functions, and VM-hosted scheduled jobs.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID. Defaults to RSV_MANAGED_IDENTITY_CLIENT_ID when set; omit for system-assigned managed identity.

.PARAMETER GraphBaseUrl
    Microsoft Graph API base URL. Supports sovereign clouds:
    https://graph.microsoft.com (commercial, default),
    https://graph.microsoft.us (GCC High),
    https://dod-graph.microsoft.us (DoD),
    https://microsoftgraph.chinacloudapi.cn (China).

.PARAMETER AuthBaseUrl
    Microsoft Entra ID token endpoint base URL. Supports sovereign clouds:
    https://login.microsoftonline.com (commercial, default),
    https://login.microsoftonline.us (GCC High),
    https://login.chinacloudapi.cn (China).

.PARAMETER LogFile
    Optional file path for persistent logging. When specified, all validation
    outcomes are appended to this file for audit and troubleshooting purposes.

.EXAMPLE
    .\Invoke-SourceValidation.ps1 -Environment "https://contoso.crm.dynamics.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$SourceId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    # legacy: dev-only - replace with managed identity in production.
    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [switch]$UseManagedIdentity,

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityClientId = $env:RSV_MANAGED_IDENTITY_CLIENT_ID,

    # Sovereign cloud support: override for Graph API base URL.
    # NOTE: GraphBaseUrl, AuthBaseUrl, and Environment must all target the same sovereign cloud.
    # Mismatched combinations (e.g., commercial Graph URL with GCC-High auth) will fail at
    # authentication with an opaque error. Valid pairings:
    #   Commercial: graph.microsoft.com      + login.microsoftonline.com  + *.crm.dynamics.com
    #   GCC-High:   graph.microsoft.us       + login.microsoftonline.us   + *.crm.microsoftdynamics.us
    #   DoD:        dod-graph.microsoft.us   + login.microsoftonline.us   + *.crm.appsplatform.us
    #   China:      microsoftgraph.chinacloudapi.cn + login.chinacloudapi.cn + *.crm.dynamics.cn
    [Parameter(Mandatory = $false)]
    [ValidateSet("https://graph.microsoft.com", "https://graph.microsoft.us", "https://dod-graph.microsoft.us", "https://microsoftgraph.chinacloudapi.cn")]
    [string]$GraphBaseUrl = "https://graph.microsoft.com",

    # Sovereign cloud support: override for Microsoft Entra ID token endpoint base URL.
    # Must match the same sovereign cloud as GraphBaseUrl and Environment (see note above).
    [Parameter(Mandatory = $false)]
    [ValidateSet("https://login.microsoftonline.com", "https://login.microsoftonline.us", "https://login.chinacloudapi.cn")]
    [string]$AuthBaseUrl = "https://login.microsoftonline.com",

    # Optional log file path for persistent logging (audit/troubleshooting).
    [Parameter(Mandatory = $false)]
    [string]$LogFile
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# File-based logging helper for scheduled/automated execution
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $entry = "$timestamp [$Level] $Message"
    if ($LogFile) {
        $logDir = Split-Path -Parent $LogFile
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        try {
            $entry | Out-File -FilePath $LogFile -Append -Encoding utf8
        } catch {
            Write-Warning "Write-Log: Failed to write to log file '$LogFile': $($_.Exception.Message)"
        }
    }
}

# Validate $Environment to prevent token exfiltration via attacker-controlled URLs
if ($Environment -notmatch '^https://[a-z0-9\-]+\.(crm[0-9]*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn)/?$') {
    throw "Invalid Environment URL '$Environment'. Expected a Dataverse environment URL (e.g., https://contoso.crm.dynamics.com)."
}
$Environment = $Environment.TrimEnd('/')

# Cross-validate that GraphBaseUrl, AuthBaseUrl, and Environment target the same sovereign cloud
$cloudPairings = @{
    Commercial = @{ Graph = "https://graph.microsoft.com";          Auth = "https://login.microsoftonline.com"; EnvPattern = 'crm[0-9]*\.dynamics\.com' }
    GCCHigh    = @{ Graph = "https://graph.microsoft.us";           Auth = "https://login.microsoftonline.us";  EnvPattern = 'crm\.microsoftdynamics\.us' }
    DoD        = @{ Graph = "https://dod-graph.microsoft.us";       Auth = "https://login.microsoftonline.us";  EnvPattern = 'crm\.appsplatform\.us' }
    China      = @{ Graph = "https://microsoftgraph.chinacloudapi.cn"; Auth = "https://login.chinacloudapi.cn"; EnvPattern = 'crm\.dynamics\.cn' }
}
$detectedCloud = $null
foreach ($cloud in $cloudPairings.GetEnumerator()) {
    if ($Environment -match $cloud.Value.EnvPattern) { $detectedCloud = $cloud.Key; break }
}
if ($detectedCloud) {
    $expected = $cloudPairings[$detectedCloud]
    if ($GraphBaseUrl -ne $expected.Graph) {
        throw "Sovereign cloud mismatch: Environment '$Environment' is $detectedCloud but GraphBaseUrl '$GraphBaseUrl' does not match expected '$($expected.Graph)'. All three parameters must target the same cloud."
    }
    if ($AuthBaseUrl -ne $expected.Auth) {
        throw "Sovereign cloud mismatch: Environment '$Environment' is $detectedCloud but AuthBaseUrl '$AuthBaseUrl' does not match expected '$($expected.Auth)'. All three parameters must target the same cloud."
    }
}

# Convert SecureString or fall back to environment variable for the legacy dev-only path.
if ($null -eq $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    # legacy: dev-only - replace with managed identity in production.
    $ClientSecret = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
}
$clientSecretPlain = if ($null -ne $ClientSecret) {
    [System.Net.NetworkCredential]::new('', $ClientSecret).Password
} else { $null }
$script:authMode = if ($UseManagedIdentity -or -not $clientSecretPlain) { "ManagedIdentity" } else { "ClientSecret" }

function Get-ClientCredentialToken {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret, [string]$Resource)

    if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
        throw "TenantId, ClientId, and ClientSecret are required for legacy client-secret authentication. Use -UseManagedIdentity in production Azure hosts."
    }

    $tokenUrl = "$AuthBaseUrl/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "$Resource/.default"
        grant_type    = "client_credentials"
    }

    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -MaximumRetryCount 3 -RetryIntervalSec 5
    return @{
        Token     = $response.access_token
        ExpiresAt = (Get-Date).AddSeconds([int]$response.expires_in - 300)  # Refresh 5 min early
        Resource  = $Resource
    }
}

function Get-ManagedIdentityToken {
    param([string]$Resource)

    $encodedResource = [System.Uri]::EscapeDataString($Resource)
    $headers = @{ Metadata = "true" }

    if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
        $tokenUrl = "$($env:IDENTITY_ENDPOINT)?api-version=2019-08-01&resource=$encodedResource"
        $headers["X-IDENTITY-HEADER"] = $env:IDENTITY_HEADER
    } elseif ($env:MSI_ENDPOINT -and $env:MSI_SECRET) {
        $tokenUrl = "$($env:MSI_ENDPOINT)?api-version=2017-09-01&resource=$encodedResource"
        $headers = @{ Secret = $env:MSI_SECRET }
    } else {
        $tokenUrl = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$encodedResource"
    }

    if ($ManagedIdentityClientId) {
        $encodedClientId = [System.Uri]::EscapeDataString($ManagedIdentityClientId)
        $tokenUrl = "$tokenUrl&client_id=$encodedClientId"
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Headers $headers -Method Get -TimeoutSec 10 -MaximumRetryCount 2 -RetryIntervalSec 2
    } catch {
        throw "Managed identity authentication failed for resource '$Resource'. Run in an Azure host with managed identity enabled, or use the legacy dev-only client-secret fallback. $($_.Exception.Message)"
    }

    return @{
        Token     = $response.access_token
        ExpiresAt = (Get-Date).AddSeconds([int]$response.expires_in - 300)
        Resource  = $Resource
    }
}

function Get-TokenInfo {
    param([string]$Resource)

    if ($script:authMode -eq "ManagedIdentity") {
        return Get-ManagedIdentityToken -Resource $Resource
    }

    $secret = if ($null -ne $ClientSecret) {
        [System.Net.NetworkCredential]::new('', $ClientSecret).Password
    } else { $null }
    return Get-ClientCredentialToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $secret -Resource $Resource
}

# Token state for automatic refresh
$script:tokenCache = @{}

function Get-ValidToken {
    param([string]$Resource)

    $cached = $script:tokenCache[$Resource]
    if ($cached -and (Get-Date) -lt $cached.ExpiresAt) {
        return $cached.Token
    }

    $tokenInfo = Get-TokenInfo -Resource $Resource
    $script:tokenCache[$Resource] = $tokenInfo
    return $tokenInfo.Token
}

function Get-ContentHash {
    param($Content)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        # Handle both byte[] (binary files from Invoke-WebRequest) and string content
        $bytes = if ($Content -is [byte[]]) { $Content } else { [System.Text.Encoding]::UTF8.GetBytes([string]$Content) }
        $hashBytes = $sha256.ComputeHash($bytes)
        return [BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
    } finally {
        $sha256.Dispose()
    }
}

function Get-SharePointContent {
    param([string]$Token, [string]$Uri)

    # Validate URI to prevent SSRF / token exfiltration (commercial + sovereign clouds)
    # Note: Direct SharePoint REST URLs (*.sharepoint.com/_api/...) are allowed by this
    # check but will fail authentication -- the script only acquires a Graph API-scoped
    # token. Use Graph API URLs (graph.microsoft.com/v1.0/sites/...) for SharePoint access.
    if ($Uri -notmatch '^https://(graph\.microsoft\.(com|us)|dod-graph\.microsoft\.us|microsoftgraph\.chinacloudapi\.cn|[a-z0-9\-]+\.sharepoint\.(com|us|cn)|[a-z0-9\-]+\.sharepoint-mil\.us)/') {
        throw "Blocked URI '$Uri': only Microsoft Graph and SharePoint domains (commercial and sovereign clouds) are allowed."
    }

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Accept" = "application/json"
    }

    try {
        # Fetch actual file content instead of metadata to avoid volatile fields
        # (lastModifiedDateTime, eTag, view counts) causing false-positive hash changes.
        $contentUri = if ($Uri -match '/items/[^/]+$') { "$Uri/content" } elseif ($Uri -match ':/.+:$') { $Uri -replace ':$', ':/content' } else { Write-Warning "URI '$Uri' does not match known Graph API content patterns (/items/{id} or :/path:). Fetching as-is; response may contain volatile metadata fields causing false-positive hash mismatches."; $Uri }
        $response = Invoke-WebRequest -Uri $contentUri -Headers $headers -Method Get -MaximumRetryCount 3 -RetryIntervalSec 5
        # Read raw bytes to ensure binary content (PDF, DOCX, etc.) is not
        # charset-decoded to a string, which would produce incorrect hashes on PS 7.0-7.3.
        $response.RawContentStream.Position = 0
        $memStream = [System.IO.MemoryStream]::new()
        try {
            $response.RawContentStream.CopyTo($memStream)
            return ,[byte[]]$memStream.ToArray()
        } finally {
            $memStream.Dispose()
        }
    } catch [System.Net.Http.HttpRequestException], [Microsoft.PowerShell.Commands.HttpResponseException] {
        throw
    } catch {
        throw "Failed to access SharePoint: $($_.Exception.Message)"
    }
}

function Get-KnowledgeSources {
    param([string]$Environment, [string]$Token, [string]$SourceId)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $filter = "fsi_status eq 1"  # Active sources
    if ($SourceId) {
        if ($SourceId -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
            throw "Invalid SourceId format: '$SourceId'. Expected GUID."
        }
        $filter = "fsi_knowledgesourceid eq $SourceId and fsi_status eq 1"
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $selectColumns = "fsi_knowledgesourceid,fsi_sourcename,fsi_description,fsi_sourcetype,fsi_sourceuri,fsi_currenthash,fsi_baselinehash,fsi_alertonchange,fsi_freshnessthreshold,fsi_lastmodified"
    $nextLink = "$Environment/api/data/v9.2/fsi_knowledgesources?`$select=$selectColumns&`$filter=$filter"
    while ($nextLink) {
        $response = Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get -MaximumRetryCount 3 -RetryIntervalSec 5
        $results.AddRange([object[]]$response.value)
        $nextLink = $response.'@odata.nextLink'
    }
    return $results
}

function New-ValidationResult {
    param([string]$Environment, [string]$Token, [hashtable]$Result)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $uri = "$Environment/api/data/v9.2/fsi_validationresults"
    $body = $Result | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body -MaximumRetryCount 3 -RetryIntervalSec 5 | Out-Null
}

function Update-SourceHash {
    param(
        [string]$Environment,
        [string]$Token,
        [string]$SourceId,
        [string]$Hash,
        [string]$BaselineHash,
        [int]$Status
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $uri = "$Environment/api/data/v9.2/fsi_knowledgesources($SourceId)"
    $update = @{
        fsi_currenthash = $Hash
        fsi_lastvalidated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    if ($BaselineHash) {
        $update.fsi_baselinehash = $BaselineHash
    }
    if ($PSBoundParameters.ContainsKey('Status')) {
        $update.fsi_status = $Status
    }
    $body = $update | ConvertTo-Json

    Invoke-RestMethod -Uri $uri -Headers $headers -Method Patch -Body $body -MaximumRetryCount 3 -RetryIntervalSec 5 | Out-Null
}

function Update-SourceStatus {
    param(
        [string]$Environment,
        [string]$Token,
        [string]$SourceId,
        [int]$Status
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $uri = "$Environment/api/data/v9.2/fsi_knowledgesources($SourceId)"
    $body = @{
        fsi_status = $Status
        fsi_lastvalidated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    } | ConvertTo-Json

    Invoke-RestMethod -Uri $uri -Headers $headers -Method Patch -Body $body -MaximumRetryCount 3 -RetryIntervalSec 5 | Out-Null
}

function New-SourceChange {
    param(
        [string]$Environment,
        [string]$Token,
        [string]$SourceId,
        [string]$SourceName,
        [int]$ChangeType,
        [string]$PreviousValue,
        [string]$NewValue,
        [string]$ChangedBy
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $sourceSlug = if ([string]::IsNullOrEmpty($SourceName)) { 'unknown' } else { ($SourceName -replace '[^A-Za-z0-9_\-]','-').Substring(0, [Math]::Min(40, $SourceName.Length)) }
    $change = @{
        "fsi_knowledgesourceid@odata.bind" = "/fsi_knowledgesources($SourceId)"
        fsi_changename = "$ChangeType-$sourceSlug-$(Get-Date -Format 'yyyyMMddHHmmssfff')"
        fsi_changetype = $ChangeType
        fsi_detectedon = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        fsi_previousvalue = $PreviousValue
        fsi_newvalue = $NewValue
        fsi_reviewed = $false
        fsi_changedby = $ChangedBy
    }

    $uri = "$Environment/api/data/v9.2/fsi_sourcechanges"
    $body = $change | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body -MaximumRetryCount 3 -RetryIntervalSec 5 | Out-Null
}

# Main script
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RAG Source Validator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Log "RAG Source Validator started. Environment: $Environment"

if ($script:authMode -eq "ClientSecret" -and (-not $TenantId -or -not $ClientId -or -not $clientSecretPlain)) {
    Write-Log "FATAL: Missing credentials for legacy client-secret fallback. Use -UseManagedIdentity in production Azure hosts, or set AZURE_TENANT_ID, AZURE_CLIENT_ID, and AZURE_CLIENT_SECRET for development." -Level "ERROR"
    Write-Error "Missing credentials for legacy client-secret fallback. Use -UseManagedIdentity in production Azure hosts, or set AZURE_TENANT_ID, AZURE_CLIENT_ID, and AZURE_CLIENT_SECRET for development."
}

Write-Host "Environment: $Environment"
Write-Host "Authentication mode: $($script:authMode)"
Write-Host ""

# Get tokens (with refresh support for long-running validations)
Write-Host "Authenticating..." -ForegroundColor Gray
$graphResource = $GraphBaseUrl
$dataverseResource = $Environment
try {
    $graphTokenInfo = Get-TokenInfo -Resource $graphResource
    $dataverseTokenInfo = Get-TokenInfo -Resource $dataverseResource
} catch {
    Write-Log "FATAL: Authentication failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}
$script:tokenCache[$graphResource] = $graphTokenInfo
$script:tokenCache[$dataverseResource] = $dataverseTokenInfo
# Clear plaintext secret from memory after initial token acquisition
$clientSecretPlain = $null
[System.GC]::Collect()
Write-Host "  Authenticated" -ForegroundColor Green

# Get sources
Write-Host ""
Write-Host "Loading knowledge sources..." -ForegroundColor Gray
$sources = Get-KnowledgeSources -Environment $Environment -Token (Get-ValidToken -Resource $dataverseResource) -SourceId $SourceId
Write-Host "  Found $($sources.Count) sources to validate"

if ($sources.Count -eq 0) {
    if ($SourceId) {
        Write-Warning "Source '$SourceId' not found or not in Active status. Sources transition to non-Active status (Validation Failed, Stale) after failures and must be manually reset to Active (1) before they are included in validation runs."
        Write-Log "WARNING: No active source found for SourceId '$SourceId'. Source may have non-Active status from a prior validation failure." -Level "WARN"
        exit 2
    } else {
        Write-Warning "No active sources found. Sources with non-Active status (Validation Failed=3, Stale=4) are excluded from validation. Reset source status to Active (1) in the Dataverse model-driven app to re-include them."
        Write-Log "WARNING: No active sources found. Check for sources with non-Active status that may need to be reset." -Level "WARN"
        exit 2
    }
}

# Validate each source
$passed = 0
$failed = 0
$changed = 0
$skipped = 0
$stale = 0

foreach ($source in $sources) {
    Write-Host ""
    Write-Host "Validating: $($source.fsi_sourcename)" -ForegroundColor White

    $startTime = Get-Date
    $sourceUpdated = $false
    $result = @{
        "fsi_knowledgesourceid@odata.bind" = "/fsi_knowledgesources($($source.fsi_knowledgesourceid))"
        fsi_resultname = "Validation-$($source.fsi_sourcename)-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        fsi_validationtime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        fsi_validationtype = 2  # On-Demand
        fsi_previoushash = $source.fsi_currenthash
    }

    try {
        # Get content based on source type
        $content = $null
        switch ($source.fsi_sourcetype) {
            1 { # SharePoint Document Library
                $content = Get-SharePointContent -Token (Get-ValidToken -Resource $graphResource) -Uri $source.fsi_sourceuri
            }
            4 { # Dataverse Table
                Write-Warning "Dataverse source validation not yet implemented for source '$($source.fsi_sourcename)'. Marking as 'Not Implemented'."
                $result.fsi_result = 7  # Skipped - Not Implemented
                $result.fsi_currenthash = $null
                $result.fsi_hashchanged = $false
                Write-Host "  SKIPPED - Dataverse validation not yet implemented" -ForegroundColor Yellow
                Write-Log "SKIPPED: $($source.fsi_sourcename) - Dataverse validation not yet implemented" -Level "WARN"
                $skipped++
                # Skip hash comparison for unsupported types
                $content = $null
            }
            {$_ -in 2,3,5,6,7,8,9,10,11,12,13} { # Planned types: SharePoint List, SharePoint Page, Azure Blob, External API, Database Query, Public Website, OneDrive, Copilot Connector, Azure AI Search, Uploaded Document
                Write-Warning "Source type $_ validation not yet implemented for source '$($source.fsi_sourcename)'. Marking as 'Not Implemented'."
                $result.fsi_result = 7  # Skipped - Not Implemented
                $result.fsi_currenthash = $null
                $result.fsi_hashchanged = $false
                Write-Host "  SKIPPED - Source type $_ validation not yet implemented" -ForegroundColor Yellow
                Write-Log "SKIPPED: $($source.fsi_sourcename) - source type $_ validation not yet implemented" -Level "WARN"
                $skipped++
                $content = $null
            }
            default {
                Write-Warning "Source type $($source.fsi_sourcetype) is unsupported for source '$($source.fsi_sourcename)'. Marking as 'Unsupported Type'."
                $result.fsi_result = 8  # Skipped - Unsupported Type
                $result.fsi_currenthash = $null
                $result.fsi_hashchanged = $false
                Write-Host "  SKIPPED - Unsupported source type" -ForegroundColor Yellow
                Write-Log "SKIPPED: $($source.fsi_sourcename) - unsupported source type $($source.fsi_sourcetype)" -Level "WARN"
                $skipped++
                $content = $null
            }
        }

        # Compute hash and compare (only for supported source types)
        if ($null -ne $content) {
            $currentHash = Get-ContentHash -Content $content
            $result.fsi_currenthash = $currentHash

            # Compare to baseline
            if ($source.fsi_baselinehash) {
                if ($currentHash -eq $source.fsi_baselinehash) {
                    $result.fsi_result = 1  # Passed
                    $result.fsi_hashchanged = $false
                    Write-Host "  PASSED - Hash matches baseline" -ForegroundColor Green
                    Write-Log "PASSED: $($source.fsi_sourcename) - hash matches baseline"
                    $passed++
                } else {
                    $result.fsi_result = 2  # Failed - Hash Mismatch
                    $result.fsi_hashchanged = $true
                    $result.fsi_changedetails = "Current hash '$currentHash' does not match baseline '$($source.fsi_baselinehash)'"
                    Write-Host "  CHANGED - Hash mismatch detected" -ForegroundColor Yellow
                    Write-Log "CHANGED: $($source.fsi_sourcename) - hash mismatch" -Level "WARN"
                    $changed++

                    # Record change in the fsi_sourcechange audit trail (skip if hash unchanged since last validation)
                    if ($currentHash -ne $source.fsi_currenthash) {
                        try {
                            New-SourceChange -Environment $Environment -Token (Get-ValidToken -Resource $dataverseResource) `
                                -SourceId $source.fsi_knowledgesourceid -SourceName $source.fsi_sourcename -ChangeType 1 `
                                -PreviousValue $source.fsi_currenthash -NewValue $currentHash `
                                -ChangedBy "RAG Source Validator"
                        } catch {
                            Write-Warning "Failed to record source change for '$($source.fsi_sourcename)': $($_.Exception.Message)"
                            Write-Log "AUDIT GAP: Source change record not created for '$($source.fsi_sourcename)'. Error: $($_.Exception.Message)" -Level "ERROR"
                        }
                    }

                    # fsi_alertonchange: alert delivery is not yet implemented
                    if ($source.fsi_alertonchange) {
                        Write-Warning "Source '$($source.fsi_sourcename)' has alerting enabled but alert delivery is not yet implemented."
                    }
                }
            } else {
                # Trust-on-first-use: no prior baseline exists, so current hash becomes the baseline.
                # WARNING: If the source is already compromised, the tampered content becomes the trusted baseline.
                Write-Warning "No baseline exists for '$($source.fsi_sourcename)'. Current hash will be captured as baseline (trust-on-first-use)."
                $result.fsi_result = 1
                $result.fsi_validationtype = 4  # Baseline Capture
                $result.fsi_hashchanged = $false
                Write-Host "  BASELINE CAPTURED (trust-on-first-use)" -ForegroundColor Cyan
                Write-Log "BASELINE CAPTURED: $($source.fsi_sourcename) - trust-on-first-use, current hash set as baseline" -Level "WARN"
                $passed++
            }

            # Freshness validation: check if source exceeds its freshness threshold.
            # Note: fsi_lastmodified must be maintained externally (e.g., via Power Automate
            # or SharePoint webhooks). This script reads but does not update it.
            if ($null -ne $source.fsi_freshnessthreshold -and $source.fsi_lastmodified) {
                $daysSinceModified = ((Get-Date).ToUniversalTime() - ([datetime]$source.fsi_lastmodified).ToUniversalTime()).TotalDays
                if ($daysSinceModified -gt $source.fsi_freshnessthreshold) {
                    Write-Host "  STALE - Last modified $([math]::Round($daysSinceModified)) days ago (threshold: $($source.fsi_freshnessthreshold) days)" -ForegroundColor Yellow
                    Write-Log "STALE: $($source.fsi_sourcename) - last modified $([math]::Round($daysSinceModified)) days ago (threshold: $($source.fsi_freshnessthreshold) days)" -Level "WARN"
                    if ($result.fsi_result -eq 2) {
                        # Preserve hash-mismatch result -- integrity violations must not be
                        # reclassified as staleness (SEC Rule 17a-4, FINRA Rule 4511(a)).
                        Write-Warning "Source '$($source.fsi_sourcename)' is also stale, but hash-mismatch result is preserved as the higher-severity finding."
                        $stale++  # Count staleness independently; counters represent conditions, not a partition
                    } else {
                        $result.fsi_result = 4  # Failed - Stale Content
                        $stale++
                        if ($result.fsi_hashchanged -eq $false -and $passed -gt 0) { $passed-- }
                    }
                }
            }

            # Update source hash and status in a single PATCH (write baseline on first run)
            $statusMap = @{ 1 = 1; 2 = 3; 3 = 3; 4 = 4; 5 = 3; 6 = 3; 7 = 1; 8 = 1 }
            $newStatus = $statusMap[[int]$result.fsi_result]
            $baselineParam = @{}
            if (-not $source.fsi_baselinehash) {
                $baselineParam.BaselineHash = $currentHash
            }
            try {
                Update-SourceHash -Environment $Environment -Token (Get-ValidToken -Resource $dataverseResource) -SourceId $source.fsi_knowledgesourceid -Hash $currentHash @baselineParam -Status $newStatus
                $sourceUpdated = $true
            } catch {
                Write-Warning "Failed to update source hash for '$($source.fsi_sourcename)': $($_.Exception.Message)"
                Write-Log "AUDIT GAP: Source hash update failed for '$($source.fsi_sourcename)' (hash=$currentHash). Error: $($_.Exception.Message)" -Level "ERROR"
            }
        }

        # Freshness validation for unsupported source types: these skip content
        # retrieval but may still have freshness metadata from Dataverse.
        if ($null -eq $content -and $null -ne $source.fsi_freshnessthreshold -and $source.fsi_lastmodified) {
            $daysSinceModified = ((Get-Date).ToUniversalTime() - ([datetime]$source.fsi_lastmodified).ToUniversalTime()).TotalDays
            if ($daysSinceModified -gt $source.fsi_freshnessthreshold) {
                Write-Host "  STALE - Last modified $([math]::Round($daysSinceModified)) days ago (threshold: $($source.fsi_freshnessthreshold) days)" -ForegroundColor Yellow
                Write-Log "STALE: $($source.fsi_sourcename) - last modified $([math]::Round($daysSinceModified)) days ago (threshold: $($source.fsi_freshnessthreshold) days)" -Level "WARN"
                $result.fsi_result = 4  # Failed - Stale Content
                $stale++
                $skipped--
            }
        }

    } catch [System.Net.Http.HttpRequestException], [Microsoft.PowerShell.Commands.HttpResponseException] {
        $result.fsi_result = 5  # Failed - Source Unavailable
        $result.fsi_hashchanged = $false
        $result.fsi_errordetails = $_.Exception.Message
        Write-Host "  FAILED - Source unavailable: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "FAILED: $($source.fsi_sourcename) - source unavailable: $($_.Exception.Message)" -Level "ERROR"
        $failed++
    } catch {
        $result.fsi_result = 6  # Failed - Unexpected Error (generic)
        $result.fsi_hashchanged = $false
        $result.fsi_errordetails = "Unexpected error ($($_.Exception.GetType().Name)): $($_.Exception.Message)"
        Write-Host "  FAILED - $($result.fsi_errordetails)" -ForegroundColor Red
        Write-Log "FAILED: $($source.fsi_sourcename) - $($result.fsi_errordetails)" -Level "ERROR"
        $failed++
    }

    $result.fsi_duration = [int]((Get-Date) - $startTime).TotalMilliseconds

    # Update fsi_knowledgesource.fsi_status to reflect validation outcome (skipped if already merged into Update-SourceHash)
    if (-not $sourceUpdated) {
        $statusMap = @{ 1 = 1; 2 = 3; 3 = 3; 4 = 4; 5 = 3; 6 = 3; 7 = 1; 8 = 1 }  # result → status: Passed/Skipped→Active, Mismatch/SchemaDrift/Unavail/Error→Failed, Stale→Stale
        $newStatus = $statusMap[[int]$result.fsi_result]
        if ($newStatus) {
            try {
                Update-SourceStatus -Environment $Environment -Token (Get-ValidToken -Resource $dataverseResource) -SourceId $source.fsi_knowledgesourceid -Status $newStatus
            } catch {
                Write-Warning "Failed to update source status for '$($source.fsi_sourcename)': $($_.Exception.Message)"
                Write-Log "AUDIT GAP: Source status update failed for '$($source.fsi_sourcename)' (status=$newStatus). Error: $($_.Exception.Message)" -Level "ERROR"
            }
        }
    }

    # Record validation result (separate try-catch to avoid skipping remaining sources)
    try {
        New-ValidationResult -Environment $Environment -Token (Get-ValidToken -Resource $dataverseResource) -Result $result
    } catch {
        Write-Warning "Failed to record validation result for '$($source.fsi_sourcename)': $($_.Exception.Message)"
        Write-Log "AUDIT GAP: Validation result record not created for '$($source.fsi_sourcename)' (result=$($result.fsi_result)). Status was updated but no fsi_validationresult exists. Error: $($_.Exception.Message)" -Level "ERROR"
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Validation Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Passed:  $passed"
Write-Host "Changed: $changed"
Write-Host "Stale:   $stale"
Write-Host "Failed:  $failed"
Write-Host "Skipped: $skipped"
Write-Log "Validation complete. Passed=$passed Changed=$changed Stale=$stale Failed=$failed Skipped=$skipped"

# Exit with non-zero code when any validation failures are detected.
# Allows CI/CD pipelines and scheduled automation to distinguish
# success from validation failure (SEC Rule 17a-4, FINRA Rule 4511(a)).
if ($failed -gt 0 -or $changed -gt 0 -or $stale -gt 0) {
    exit 1
}
