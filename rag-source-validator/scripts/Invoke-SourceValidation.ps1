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

function Get-AccessToken {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret, [string]$Scope)

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = "client_credentials"
    }

    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
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
        $response = Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get
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
        $filter = "fsi_knowledgesourceid eq $SourceId"
    }

    $results = @()
    $nextLink = "$Environment/api/data/v9.2/fsi_knowledgesources?`$filter=$filter"
    while ($nextLink) {
        $response = Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get
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

    Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body | Out-Null
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

    Invoke-RestMethod -Uri $uri -Headers $headers -Method Patch -Body $body | Out-Null
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
                Write-Warning "Dataverse source validation not yet implemented for source '$($source.fsi_name)'. Marking as 'RequiresManualReview'."
                $result.fsi_result = 3  # RequiresManualReview
                $result.fsi_currenthash = $null
                $result.fsi_hashchanged = $false
                $result.fsi_validationstatus = "RequiresManualReview"
                Write-Host "  SKIPPED - Dataverse validation not yet implemented" -ForegroundColor Yellow
                $skipped++
                # Skip hash comparison for unsupported types
                $content = $null
            }
            default {
                Write-Warning "Source type $($source.fsi_sourcetype) not yet supported for source '$($source.fsi_name)'. Marking as 'Unsupported'."
                $result.fsi_result = 3  # Unsupported
                $result.fsi_currenthash = $null
                $result.fsi_hashchanged = $false
                $result.fsi_validationstatus = "Unsupported"
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
        $result.fsi_errordetails = $_.Exception.Message
        Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }

    $result.fsi_duration = ((Get-Date) - $startTime).TotalMilliseconds

    # Record validation result
    New-ValidationResult -Environment $Environment -Token $dataverseToken -Result $result
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
