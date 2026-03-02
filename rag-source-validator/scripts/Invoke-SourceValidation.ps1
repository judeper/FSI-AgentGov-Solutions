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

    # Production deployments should use certificate-based auth or managed identities.
    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# Convert SecureString or fall back to environment variable
if ($null -eq $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    $ClientSecret = ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force
}
$clientSecretPlain = if ($null -ne $ClientSecret) {
    [System.Net.NetworkCredential]::new('', $ClientSecret).Password
} else { $null }

function Get-AccessToken {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret, [string]$Scope)

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = "client_credentials"
    }

    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -MaximumRetryCount 3 -RetryIntervalSec 5
    return @{
        Token     = $response.access_token
        ExpiresAt = (Get-Date).AddSeconds($response.expires_in - 300)  # Refresh 5 min early
        Scope     = $Scope
    }
}

# Token state for automatic refresh
$script:tokenCache = @{}

function Get-ValidToken {
    param([string]$Scope)

    $cached = $script:tokenCache[$Scope]
    if ($cached -and (Get-Date) -lt $cached.ExpiresAt) {
        return $cached.Token
    }

    # Re-acquire token using SecureString (clientSecretPlain may already be cleared)
    $secret = if ($null -ne $ClientSecret) {
        [System.Net.NetworkCredential]::new('', $ClientSecret).Password
    } else { $null }

    $tokenInfo = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $secret -Scope $Scope
    $script:tokenCache[$Scope] = $tokenInfo
    return $tokenInfo.Token
}

function Get-ContentHash {
    param([string]$Content)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
        $hashBytes = $sha256.ComputeHash($bytes)
        return [BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
    } finally {
        $sha256.Dispose()
    }
}

function Get-SharePointContent {
    param([string]$Token, [string]$Uri)

    # Validate URI to prevent SSRF / token exfiltration
    if ($Uri -notmatch '^https://(graph\.microsoft\.com|[a-z0-9\-]+\.sharepoint\.com)/') {
        throw "Blocked URI '$Uri': only graph.microsoft.com and *.sharepoint.com are allowed."
    }

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Accept" = "application/json"
    }

    try {
        # Fetch actual file content instead of metadata to avoid volatile fields
        # (lastModifiedDateTime, eTag, view counts) causing false-positive hash changes.
        $contentUri = if ($Uri -match '/items/[^/]+$') { "$Uri/content" } else { $Uri }
        $response = Invoke-WebRequest -Uri $contentUri -Headers $headers -Method Get -MaximumRetryCount 3 -RetryIntervalSec 5
        return [System.Text.Encoding]::UTF8.GetString($response.Content)
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

    $results = @()
    $nextLink = "$Environment/api/data/v9.2/fsi_knowledgesources?`$filter=$filter"
    while ($nextLink) {
        $response = Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get -MaximumRetryCount 3 -RetryIntervalSec 5
        $results += $response.value
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
        [string]$BaselineHash
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
    $body = $update | ConvertTo-Json

    Invoke-RestMethod -Uri $uri -Headers $headers -Method Patch -Body $body -MaximumRetryCount 3 -RetryIntervalSec 5 | Out-Null
}

# Main script
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RAG Source Validator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not $TenantId -or -not $ClientId -or -not $clientSecretPlain) {
    Write-Error "Missing credentials. Set environment variables."
    exit 1
}

Write-Host "Environment: $Environment"
Write-Host ""

# Get tokens (with refresh support for long-running validations)
Write-Host "Authenticating..." -ForegroundColor Gray
$graphScope = "https://graph.microsoft.com/.default"
$dataverseScope = "$Environment/.default"
$graphTokenInfo = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $clientSecretPlain -Scope $graphScope
$dataverseTokenInfo = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $clientSecretPlain -Scope $dataverseScope
$script:tokenCache[$graphScope] = $graphTokenInfo
$script:tokenCache[$dataverseScope] = $dataverseTokenInfo
# Clear plaintext secret from memory after initial token acquisition
$clientSecretPlain = $null
[System.GC]::Collect()
Write-Host "  Authenticated" -ForegroundColor Green

# Get sources
Write-Host ""
Write-Host "Loading knowledge sources..." -ForegroundColor Gray
$sources = Get-KnowledgeSources -Environment $Environment -Token (Get-ValidToken -Scope $dataverseScope) -SourceId $SourceId
Write-Host "  Found $($sources.Count) sources to validate"

# Validate each source
$passed = 0
$failed = 0
$changed = 0
$skipped = 0
$stale = 0

foreach ($source in $sources) {
    Write-Host ""
    Write-Host "Validating: $($source.fsi_name)" -ForegroundColor White

    $startTime = Get-Date
    $result = @{
        "fsi_knowledgesourceid@odata.bind" = "/fsi_knowledgesources($($source.fsi_knowledgesourceid))"
        fsi_validationtime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        fsi_validationtype = 2  # On-Demand
        fsi_previoushash = $source.fsi_currenthash
    }

    try {
        # Get content based on source type
        $content = ""
        switch ($source.fsi_sourcetype) {
            1 { # SharePoint Document Library
                $content = Get-SharePointContent -Token (Get-ValidToken -Scope $graphScope) -Uri $source.fsi_sourceuri
            }
            4 { # Dataverse Table
                Write-Warning "Dataverse source validation not yet implemented for source '$($source.fsi_name)'. Marking as 'RequiresManualReview'."
                $result.fsi_result = 7  # Skipped - Not Implemented
                $result.fsi_currenthash = $null
                $result.fsi_hashchanged = $false
                Write-Host "  SKIPPED - Dataverse validation not yet implemented" -ForegroundColor Yellow
                $skipped++
                # Skip hash comparison for unsupported types
                $content = $null
            }
            default {
                Write-Warning "Source type $($source.fsi_sourcetype) not yet supported for source '$($source.fsi_name)'. Marking as 'Unsupported'."
                $result.fsi_result = 8  # Skipped - Unsupported Type
                $result.fsi_currenthash = $null
                $result.fsi_hashchanged = $false
                Write-Host "  SKIPPED - Source type not yet supported" -ForegroundColor Yellow
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
                    $passed++
                } else {
                    $result.fsi_result = 2  # Failed - Hash Mismatch
                    $result.fsi_hashchanged = $true
                    Write-Host "  CHANGED - Hash mismatch detected" -ForegroundColor Yellow
                    $changed++
                }
            } else {
                # Trust-on-first-use: no prior baseline exists, so current hash becomes the baseline.
                # WARNING: If the source is already compromised, the tampered content becomes the trusted baseline.
                Write-Warning "No baseline exists for '$($source.fsi_name)'. Current hash will be captured as baseline (trust-on-first-use)."
                $result.fsi_result = 1
                $result.fsi_hashchanged = $false
                Write-Host "  BASELINE CAPTURED (trust-on-first-use)" -ForegroundColor Cyan
                $passed++
            }

            # Update source hash (write baseline on first run)
            $baselineParam = @{}
            if (-not $source.fsi_baselinehash) {
                $baselineParam.BaselineHash = $currentHash
            }
            try {
                Update-SourceHash -Environment $Environment -Token (Get-ValidToken -Scope $dataverseScope) -SourceId $source.fsi_knowledgesourceid -Hash $currentHash @baselineParam
            } catch {
                Write-Warning "Failed to update source hash for '$($source.fsi_name)': $($_.Exception.Message)"
            }
        }

        # Freshness validation: check if source exceeds its freshness threshold
        if ($source.fsi_freshnessthreshold -and $source.fsi_lastmodified) {
            $daysSinceModified = ((Get-Date).ToUniversalTime() - [datetime]$source.fsi_lastmodified).TotalDays
            if ($daysSinceModified -gt $source.fsi_freshnessthreshold) {
                $result.fsi_result = 4  # Failed - Stale Content
                Write-Host "  STALE - Last modified $([math]::Round($daysSinceModified)) days ago (threshold: $($source.fsi_freshnessthreshold) days)" -ForegroundColor Yellow
                $stale++
                # Adjust counters: un-count any prior pass from hash check
                if ($result.fsi_hashchanged -eq $false -and $passed -gt 0) { $passed-- }
            }
        }

    } catch [System.Net.Http.HttpRequestException] {
        $result.fsi_result = 5  # Failed - Source Unavailable
        $result.fsi_hashchanged = $false
        $result.fsi_errordetails = $_.Exception.Message
        Write-Host "  FAILED - Source unavailable: $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    } catch {
        $result.fsi_result = 5  # Failed - Unexpected Error
        $result.fsi_hashchanged = $false
        $result.fsi_errordetails = "Unexpected error ($($_.Exception.GetType().Name)): $($_.Exception.Message)"
        Write-Host "  FAILED - $($result.fsi_errordetails)" -ForegroundColor Red
        $failed++
    }

    $result.fsi_duration = [int]((Get-Date) - $startTime).TotalMilliseconds

    # Record validation result (separate try-catch to avoid skipping remaining sources)
    try {
        New-ValidationResult -Environment $Environment -Token (Get-ValidToken -Scope $dataverseScope) -Result $result
    } catch {
        Write-Warning "Failed to record validation result for '$($source.fsi_name)': $($_.Exception.Message)"
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
