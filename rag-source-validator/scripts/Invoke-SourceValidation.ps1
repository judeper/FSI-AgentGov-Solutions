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

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = $env:AZURE_CLIENT_SECRET
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

function Invoke-RestMethodWithRetry {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Method = "Get",
        [hashtable]$Headers,
        [object]$Body,
        [string]$ContentType,
        [int]$MaxRetries = 3
    )

    $splat = @{ Uri = $Uri; Method = $Method }
    if ($Headers) { $splat.Headers = $Headers }
    if ($null -ne $Body) { $splat.Body = $Body }
    if ($ContentType) { $splat.ContentType = $ContentType }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            return Invoke-RestMethod @splat
        } catch {
            $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 0 }
            if ($attempt -eq $MaxRetries -or $statusCode -notin @(429, 503, 504)) {
                throw
            }
            $delay = [Math]::Pow(2, $attempt)
            Write-Warning "HTTP $statusCode on attempt $attempt/$MaxRetries. Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-AccessToken {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret, [string]$Scope)

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = "client_credentials"
    }

    $response = Invoke-RestMethodWithRetry -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    return $response.access_token
}

function Get-ContentHash {
    param([string]$Content)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $hashBytes = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
}

function Get-SharePointContent {
    param([string]$Token, [string]$Uri)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Accept" = "application/json"
    }

    try {
        $response = Invoke-RestMethodWithRetry -Uri $Uri -Headers $headers -Method Get
        return $response | ConvertTo-Json -Depth 10
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
        $filter = "fsi_knowledgesourceid eq '$SourceId' and fsi_status eq 1"
    }

    $results = @()
    $nextLink = "$Environment/api/data/v9.2/fsi_knowledgesources?`$filter=$filter"
    while ($nextLink) {
        $response = Invoke-RestMethodWithRetry -Uri $nextLink -Headers $headers -Method Get
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

    Invoke-RestMethodWithRetry -Uri $uri -Headers $headers -Method Post -Body $body | Out-Null
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

    Invoke-RestMethodWithRetry -Uri $uri -Headers $headers -Method Patch -Body $body | Out-Null
}

function New-SourceChange {
    param(
        [string]$Environment,
        [string]$Token,
        [string]$SourceId,
        [int]$ChangeType,
        [string]$PreviousValue,
        [string]$NewValue
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $change = @{
        "fsi_knowledgesourceid@odata.bind" = "/fsi_knowledgesources($SourceId)"
        fsi_changetype = $ChangeType
        fsi_detectedon = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        fsi_previousvalue = $PreviousValue
        fsi_newvalue = $NewValue
        fsi_reviewed = $false
    }

    $uri = "$Environment/api/data/v9.2/fsi_sourcechanges"
    $body = $change | ConvertTo-Json -Depth 5

    Invoke-RestMethodWithRetry -Uri $uri -Headers $headers -Method Post -Body $body | Out-Null
}

# Main script
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RAG Source Validator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Error "Missing credentials. Set environment variables."
    exit 1
}

Write-Host "Environment: $Environment"
Write-Host ""

# Get tokens
Write-Host "Authenticating..." -ForegroundColor Gray
$graphToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "https://graph.microsoft.com/.default"
$dataverseToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default"
Write-Host "  Authenticated" -ForegroundColor Green

# Get sources
Write-Host ""
Write-Host "Loading knowledge sources..." -ForegroundColor Gray
$sources = Get-KnowledgeSources -Environment $Environment -Token $dataverseToken -SourceId $SourceId
Write-Host "  Found $($sources.Count) sources to validate"

# Validate each source
$passed = 0
$failed = 0
$changed = 0
$skipped = 0
$writeFailures = 0

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
                $content = Get-SharePointContent -Token $graphToken -Uri $source.fsi_sourceuri
            }
            4 { # Dataverse Table
                Write-Warning "Dataverse source validation not yet implemented for source '$($source.fsi_name)'. Skipping."
                Write-Host "  SKIPPED - Dataverse validation not yet implemented" -ForegroundColor Yellow
                $skipped++
                $result.fsi_result = 7  # Skipped - Not Yet Implemented
                $result.fsi_hashchanged = $false
                $result.fsi_duration = [int]((Get-Date) - $startTime).TotalMilliseconds
                try {
                    New-ValidationResult -Environment $Environment -Token $dataverseToken -Result $result
                } catch {
                    Write-Warning "Failed to record skip result for $($source.fsi_name): $($_.Exception.Message)"
                    $writeFailures++
                }
                continue
            }
            default {
                Write-Warning "Source type $($source.fsi_sourcetype) not yet supported for source '$($source.fsi_name)'. Skipping."
                Write-Host "  SKIPPED - Source type not yet supported" -ForegroundColor Yellow
                $skipped++
                $result.fsi_result = 7  # Skipped - Not Yet Implemented
                $result.fsi_hashchanged = $false
                $result.fsi_duration = [int]((Get-Date) - $startTime).TotalMilliseconds
                try {
                    New-ValidationResult -Environment $Environment -Token $dataverseToken -Result $result
                } catch {
                    Write-Warning "Failed to record skip result for $($source.fsi_name): $($_.Exception.Message)"
                    $writeFailures++
                }
                continue
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
                    try {
                        New-SourceChange -Environment $Environment -Token $dataverseToken `
                            -SourceId $source.fsi_knowledgesourceid -ChangeType 1 `
                            -PreviousValue $source.fsi_baselinehash -NewValue $currentHash
                    } catch {
                        Write-Warning "Failed to record source change: $($_.Exception.Message)"
                    }
                }
            } else {
                # No baseline - capture it and write back as baseline
                $result.fsi_result = 1
                $result.fsi_hashchanged = $false
                Write-Host "  BASELINE CAPTURED" -ForegroundColor Cyan
                $passed++
            }

            # Update source hash (write baseline on first run)
            $baselineParam = @{}
            if (-not $source.fsi_baselinehash) {
                $baselineParam.BaselineHash = $currentHash
            }
            Update-SourceHash -Environment $Environment -Token $dataverseToken -SourceId $source.fsi_knowledgesourceid -Hash $currentHash @baselineParam
        }

    } catch {
        $result.fsi_result = 5  # Failed - Source Unavailable
        $result.fsi_hashchanged = $false
        $result.fsi_errordetails = $_.Exception.Message
        Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }

    $result.fsi_duration = [int]((Get-Date) - $startTime).TotalMilliseconds

    # Record validation result
    try {
        New-ValidationResult -Environment $Environment -Token $dataverseToken -Result $result
    } catch {
        Write-Warning "Failed to record result for $($source.fsi_name): $($_.Exception.Message)"
        $writeFailures++
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
Write-Host "Failed:  $failed"
Write-Host "Skipped: $skipped"
if ($writeFailures -gt 0) {
    Write-Host "Write Failures: $writeFailures" -ForegroundColor Red
}

if ($failed -gt 0 -or $writeFailures -gt 0) {
    exit 1
}
if ($changed -gt 0) {
    Write-Warning "Integrity changes detected ($changed source(s)). Exit code 2."
    exit 2
}
