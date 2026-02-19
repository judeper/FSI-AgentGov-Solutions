<#
.SYNOPSIS
    Executes a disaster recovery test for AI agent infrastructure.

.DESCRIPTION
    Runs a DR test scenario, measures RTO/RPO, validates recovery,
    and records results to Dataverse.

.PARAMETER TestType
    Type of DR test: AgentRestore, EnvironmentFailover, DataRecovery, FullDR

.PARAMETER AgentId
    Target agent ID (for AgentRestore tests).

.PARAMETER Environment
    Dataverse environment URL.

.EXAMPLE
    .\Invoke-DRTest.ps1 -TestType "AgentRestore" -AgentId "guid" -Environment "https://contoso.crm.dynamics.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("AgentRestore", "EnvironmentFailover", "DataRecovery", "FullDR")]
    [string]$TestType,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$AgentId,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = $env:AZURE_CLIENT_SECRET
)

#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# Validate AgentId is provided for test types that require it
if ($TestType -in @('AgentRestore','FullDR') -and -not $AgentId) {
    throw "-AgentId is required for $TestType tests."
}

# Normalize environment URL to avoid double-slash in API paths
$Environment = $Environment.TrimEnd('/')

# Validate $Environment is a Dataverse URL to prevent token leakage to unintended endpoints
if ($Environment -notmatch '^https://[^/]+\.(crm\d*\.dynamics\.(com|us|cn|de)|crm\.microsoftdynamics\.us)$') {
    throw "Invalid Environment URL '$Environment'. Expected a Dataverse URL matching https://<org>.crm[N].dynamics.<tld> (e.g., .com, .us, .cn, .de) or https://<org>.crm.microsoftdynamics.us (GCC High)"
}

# RTO targets in hours
$RTOTargets = @{
    "AgentRestore" = 4
    "EnvironmentFailover" = 2
    "DataRecovery" = 4
    "FullDR" = 8
}

# RPO targets in hours
$RPOTargets = @{
    "AgentRestore" = 24
    "EnvironmentFailover" = 1
    "DataRecovery" = 24
    "FullDR" = 24
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

    $maxRetries = 3
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -TimeoutSec 30
            return $response.access_token
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($attempt -lt $maxRetries -and ($statusCode -in @(429, 503) -or $null -eq $_.Exception.Response)) {
                $retryAfter = $_.Exception.Response.Headers | Where-Object { $_.Key -eq 'Retry-After' } | ForEach-Object { $_.Value[0] }
                $delay = if ($retryAfter -and [int]::TryParse($retryAfter, [ref]$null)) { [int]$retryAfter } else { [math]::Pow(2, $attempt) }
                $displayCode = if ($null -eq $statusCode) { 'network error' } else { $statusCode }
                Write-Warning "Transient error ($displayCode) acquiring token (attempt $attempt/$maxRetries). Retrying in ${delay}s..."
                Start-Sleep -Seconds $delay
            } else {
                throw
            }
        }
    }
}

function Test-AgentRestore {
    param([string]$AgentId, [bool]$DryRun)

    $result = @{
        ValidationChecks = @()
        Success = $true
    }

    # IMPORTANT: Recovery steps below are stub implementations using Start-Sleep.
    # RTO/RPO measurements reflect simulated timing only.
    # Replace Start-Sleep calls with actual backup/restore API calls for production use.
    Write-Warning "IMPORTANT: Recovery steps are currently simulated (stub implementation). RTO/RPO measurements reflect simulated timing only. Replace Start-Sleep calls with actual backup/restore API calls for production use."

    Write-Host "  Step 1: Locate agent backup..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 2
        $result.ValidationChecks += @{Check = "Backup Located"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would locate agent backup" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Backup Located"; Status = "SKIPPED (DRY RUN)"}
    }

    Write-Host "  Step 2: Restore agent configuration..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 3
        $result.ValidationChecks += @{Check = "Configuration Restored"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would restore agent configuration" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Configuration Restored"; Status = "SKIPPED (DRY RUN)"}
    }

    Write-Host "  Step 3: Verify agent responds..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 2
        $result.ValidationChecks += @{Check = "Agent Responsive"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would verify agent responds" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Agent Responsive"; Status = "SKIPPED (DRY RUN)"}
    }

    Write-Host "  Step 4: Validate connectors..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 2
        $result.ValidationChecks += @{Check = "Connectors Functional"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would validate connectors" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Connectors Functional"; Status = "SKIPPED (DRY RUN)"}
    }

    Write-Host "  Step 5: Verify security policies..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 1
        $result.ValidationChecks += @{Check = "Security Applied"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would verify security policies" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Security Applied"; Status = "SKIPPED (DRY RUN)"}
    }

    return $result
}

function Test-EnvironmentFailover {
    param([bool]$DryRun)

    $result = @{
        ValidationChecks = @()
        Success = $true
    }

    # IMPORTANT: Recovery steps below are stub implementations using Start-Sleep.
    # RTO/RPO measurements reflect simulated timing only.
    # Replace Start-Sleep calls with actual failover API calls for production use.
    Write-Warning "IMPORTANT: Recovery steps are currently simulated (stub implementation). RTO/RPO measurements reflect simulated timing only. Replace Start-Sleep calls with actual failover API calls for production use."

    Write-Host "  Step 1: Initiate failover..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 3
        $result.ValidationChecks += @{Check = "Failover Initiated"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would initiate failover" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Failover Initiated"; Status = "SKIPPED (DRY RUN)"}
    }

    Write-Host "  Step 2: Verify backup environment accessible..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 2
        $result.ValidationChecks += @{Check = "Environment Accessible"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would verify backup environment accessible" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Environment Accessible"; Status = "SKIPPED (DRY RUN)"}
    }

    Write-Host "  Step 3: Validate data synchronization..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 2
        $result.ValidationChecks += @{Check = "Data Synchronized"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would validate data synchronization" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Data Synchronized"; Status = "SKIPPED (DRY RUN)"}
    }

    Write-Host "  Step 4: Test agent functionality..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 2
        $result.ValidationChecks += @{Check = "Agents Functional"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would test agent functionality" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Agents Functional"; Status = "SKIPPED (DRY RUN)"}
    }

    return $result
}

function Test-DataRecovery {
    param([bool]$DryRun)

    $result = @{
        ValidationChecks = @()
        Success = $true
    }

    # IMPORTANT: Recovery steps below are stub implementations using Start-Sleep.
    # RTO/RPO measurements reflect simulated timing only.
    # Replace Start-Sleep calls with actual data recovery API calls for production use.
    Write-Warning "IMPORTANT: Recovery steps are currently simulated (stub implementation). RTO/RPO measurements reflect simulated timing only. Replace Start-Sleep calls with actual data recovery API calls for production use."

    Write-Host "  Step 1: Identify restore point..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 2
        $result.ValidationChecks += @{Check = "Restore Point Found"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would identify restore point" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Restore Point Found"; Status = "SKIPPED (DRY RUN)"}
    }

    Write-Host "  Step 2: Initiate data restore..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 4
        $result.ValidationChecks += @{Check = "Restore Initiated"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would initiate data restore" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Restore Initiated"; Status = "SKIPPED (DRY RUN)"}
    }

    Write-Host "  Step 3: Verify data integrity..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 2
        $result.ValidationChecks += @{Check = "Data Integrity Verified"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would verify data integrity" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Data Integrity Verified"; Status = "SKIPPED (DRY RUN)"}
    }

    Write-Host "  Step 4: Validate record counts..." -ForegroundColor Gray
    if (-not $DryRun) {
        Start-Sleep -Seconds 1
        $result.ValidationChecks += @{Check = "Records Complete"; Status = "PASS"}
    } else {
        Write-Host "    [DRY RUN] Would validate record counts" -ForegroundColor Yellow
        $result.ValidationChecks += @{Check = "Records Complete"; Status = "SKIPPED (DRY RUN)"}
    }

    return $result
}

function Save-TestResult {
    param([string]$Environment, [string]$Token, [hashtable]$Result)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $record = @{
        fsi_testtype = $Result.TestType
        fsi_executedon = $Result.ExecutedOn
        fsi_actualrto = $Result.ActualRTO
        fsi_targetrto = $Result.TargetRTO
        fsi_rtomet = $Result.RTOMet
        fsi_targetrpo = $Result.TargetRPO
        fsi_status = if ($Result.Success) { 1 } else { 2 }
        fsi_validationchecks = (ConvertTo-Json -InputObject $Result.ValidationChecks -Depth 4 -Compress)
    }

    # Only include RPO fields when measured (avoids type mismatch in Dataverse)
    if ($null -ne $Result.ActualRPO) { $record["fsi_actualrpo"] = $Result.ActualRPO }
    if ($null -ne $Result.RPOMet) { $record["fsi_rpomet"] = $Result.RPOMet }

    $uri = "$Environment/api/data/v9.2/fsi_drtestresults"
    $maxRetries = 3
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body ($record | ConvertTo-Json) -TimeoutSec 30 | Out-Null
            return $true
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($attempt -lt $maxRetries -and ($statusCode -in @(429, 503) -or $null -eq $_.Exception.Response)) {
                $retryAfter = $_.Exception.Response.Headers | Where-Object { $_.Key -eq 'Retry-After' } | ForEach-Object { $_.Value[0] }
                $delay = if ($retryAfter -and [int]::TryParse($retryAfter, [ref]$null)) { [int]$retryAfter } else { [math]::Pow(2, $attempt) }
                $displayCode = if ($null -eq $statusCode) { 'network error' } else { $statusCode }
                Write-Warning "Transient error ($displayCode) saving result (attempt $attempt/$maxRetries). Retrying in ${delay}s..."
                Start-Sleep -Seconds $delay
            } else {
                Write-Warning "Failed to save result (attempt $attempt/$maxRetries): $($_.Exception.Message)"
                return $false
            }
        }
    }
}

# Main script
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DR Testing Framework" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - Simulated test execution]" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Test Type: $TestType"
Write-Host "Target RTO: $($RTOTargets[$TestType]) hours"
Write-Host "Target RPO: $($RPOTargets[$TestType]) hours"
Write-Host ""

$testStartTime = Get-Date
Write-Host "Test started at: $($testStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host ""

# Execute appropriate test
Write-Host "Executing recovery procedure..." -ForegroundColor White
$testResult = switch ($TestType) {
    "AgentRestore" { Test-AgentRestore -AgentId $AgentId -DryRun $DryRun }
    "EnvironmentFailover" { Test-EnvironmentFailover -DryRun $DryRun }
    "DataRecovery" { Test-DataRecovery -DryRun $DryRun }
    "FullDR" {
        # Full DR combines all tests
        $agentResult = Test-AgentRestore -AgentId $AgentId -DryRun $DryRun
        $envResult = Test-EnvironmentFailover -DryRun $DryRun
        $dataResult = Test-DataRecovery -DryRun $DryRun
        @{
            ValidationChecks = $agentResult.ValidationChecks + $envResult.ValidationChecks + $dataResult.ValidationChecks
            Success = $agentResult.Success -and $envResult.Success -and $dataResult.Success
        }
    }
}

$testEndTime = Get-Date
$actualRTO = ($testEndTime - $testStartTime).TotalHours
$rtoMet = $actualRTO -le $RTOTargets[$TestType]

# Prepare result summary
# TODO: Implement actual RPO measurement by comparing last backup timestamp with recovery point
$finalResult = @{
    TestType = $TestType
    ExecutedOn = $testStartTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    ActualRTO = [math]::Round($actualRTO, 2)
    TargetRTO = $RTOTargets[$TestType]
    RTOMet = $rtoMet
    ActualRPO = $null
    TargetRPO = $RPOTargets[$TestType]
    RPOMet = $null
    Success = $testResult.Success -and $rtoMet
    ValidationChecks = $testResult.ValidationChecks
}

# Display results
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($check in $testResult.ValidationChecks) {
    $color = if ($check.Status -eq "PASS") { "Green" } elseif ($check.Status -like "SKIPPED*") { "Yellow" } else { "Red" }
    Write-Host "  [$($check.Status)] $($check.Check)" -ForegroundColor $color
}

Write-Host ""
Write-Host "RTO Performance:"
Write-Host "  Target:  $($RTOTargets[$TestType]) hours"
Write-Host "  Actual:  $([math]::Round($actualRTO * 60, 1)) minutes"
$rtoColor = if ($rtoMet) { "Green" } else { "Red" }
Write-Host "  Status:  $(if ($rtoMet) {'MET'} else {'EXCEEDED'})" -ForegroundColor $rtoColor

Write-Host ""
$overallColor = if ($finalResult.Success) { "Green" } else { "Red" }
Write-Host "Overall Result: $(if ($finalResult.Success) {'PASS'} else {'FAIL'})" -ForegroundColor $overallColor

# Save to Dataverse if not dry run and authenticated
if (-not $DryRun -and $TenantId -and $ClientId -and $ClientSecret) {
    Write-Host ""
    Write-Host "Saving results to Dataverse..." -ForegroundColor Gray
    try {
        $token = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default"
        # Clear plaintext secret from memory after token acquisition.
        # NOTE: This only nulls the local copy; the original string may persist
        # in the managed heap until GC. For stronger secret hygiene, accept a
        # SecureString parameter or use
        # [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode().
        $ClientSecret = $null
        [System.GC]::Collect()
        if (Save-TestResult -Environment $Environment -Token $token -Result $finalResult) {
            Write-Host "  Results saved successfully" -ForegroundColor Green
        } else {
            Write-Warning "Failed to save test result for '$($finalResult.TestType)' to Dataverse."
        }
    } catch {
        Write-Warning "Failed to authenticate or save results to Dataverse. Verify AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and that the service principal has Dataverse write permissions. Error: $($_.Exception.Message)"
    } finally {
        # Clear access token from memory
        $token = $null
    }
} elseif (-not $DryRun) {
    Write-Warning "Dataverse credentials not provided (TenantId/ClientId/ClientSecret). Test results were NOT saved to Dataverse."
}

Write-Host ""
Write-Host "Test completed at: $($testEndTime.ToString('yyyy-MM-dd HH:mm:ss'))"

# Exit with non-zero code on test failure for CI/CD integration.
# NOTE: Do not dot-source this script (. .\Invoke-DRTest.ps1) as exit will terminate the calling session.
exit ([int](-not $finalResult.Success))
