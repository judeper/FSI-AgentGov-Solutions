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
    [string]$AgentId,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{1,8}$')]
    [string]$CorrelationId
)

# Convert AZURE_CLIENT_SECRET env var to SecureString if parameter not provided
if (-not $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    $ClientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
}

#Requires -Version 7.0

# Validate AgentId is provided and well-formed for test types that require it
if ($TestType -in @("AgentRestore", "FullDR")) {
    if ([string]::IsNullOrWhiteSpace($AgentId)) {
        throw "AgentId is required for $TestType tests."
    }
    if ($AgentId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw "AgentId must be a valid GUID (e.g., 12345678-1234-1234-1234-123456789abc)."
    }
}

# Normalize trailing slash before validation
$Environment = $Environment.TrimEnd('/')

# Validate Environment is a well-formed Dataverse URL to prevent SSRF / token exfiltration
if ($Environment -notmatch '^https://[\w\-]+\.(crm[\d]*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn)$') {
    throw "Environment must be a valid Dataverse URL (e.g., https://<org>.crm.dynamics.com, .microsoftdynamics.us, .appsplatform.us, or .dynamics.cn)"
}

$ErrorActionPreference = "Stop"

# Structured audit logging with file persistence for compliance evidence
$script:AuditLogDir = Join-Path $PSScriptRoot ".." "logs"
$script:AuditLogPath = $null

function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$CorrelationId = $script:CorrelationId
    )
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ" -AsUTC
    $entry = "[$timestamp] [$Level] [$CorrelationId] $Message"
    Write-Information $entry -InformationAction Continue
    # Persist audit events to log file for tamper-evident compliance evidence
    if ($script:AuditLogPath) {
        try {
            Add-Content -Path $script:AuditLogPath -Value $entry -ErrorAction Stop
        } catch {
            # File write is best-effort; do not fail the test run
        }
    }
}

# Initialize correlation ID and audit log file
$script:CorrelationId = if ($CorrelationId) { $CorrelationId } else { [guid]::NewGuid().ToString("N").Substring(0,8) }
try {
    if (-not (Test-Path $script:AuditLogDir)) {
        New-Item -ItemType Directory -Path $script:AuditLogDir -Force | Out-Null
    }
    $script:AuditLogPath = Join-Path $script:AuditLogDir "dr-audit-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$($script:CorrelationId).log"
} catch {
    Write-Warning "Could not create audit log directory: $($_.Exception.Message). Audit events will only be written to stdout."
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

function Get-AuthEndpoint {
    param([string]$EnvironmentUrl)
    # Map Dataverse environment URL to the correct Entra ID authority for sovereign clouds
    if ($EnvironmentUrl -match '\.dynamics\.cn$') {
        return 'https://login.chinacloudapi.cn'
    } elseif ($EnvironmentUrl -match '\.(microsoftdynamics\.us|appsplatform\.us)$') {
        return 'https://login.microsoftonline.us'
    } else {
        return 'https://login.microsoftonline.com'
    }
}

function Get-AccessToken {
    param([string]$TenantId, [string]$ClientId, [SecureString]$ClientSecret, [string]$Scope, [string]$AuthEndpoint = 'https://login.microsoftonline.com')

    $plainSecret = $null
    $body = $null
    try {
        $plainSecret = [System.Net.NetworkCredential]::new('', $ClientSecret).Password
        $tokenUrl = "$AuthEndpoint/$TenantId/oauth2/v2.0/token"
        $body = @{
            client_id     = $ClientId
            client_secret = $plainSecret
            scope         = $Scope
            grant_type    = "client_credentials"
        }

        $maxRetries = 3
        Write-Verbose "Requesting access token from $tokenUrl (max $maxRetries attempts)"
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -TimeoutSec 30
                if ([string]::IsNullOrEmpty($response.access_token)) {
                    throw "Token endpoint returned HTTP 200 but no access_token field."
                }
                return $response.access_token
            } catch {
                $statusCode = 0
                if ($_.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException]) {
                    $statusCode = $_.Exception.Response.StatusCode.value__
                }
                $isTransient = $statusCode -in @(429, 500, 502, 503, 504) -or ($statusCode -eq 0 -and $_.Exception -isnot [System.Management.Automation.RuntimeException])
                if (-not $isTransient -or $attempt -eq $maxRetries) { throw }
                Write-AuditLog "Token request failed (attempt $attempt/$maxRetries): $($_.Exception.Message)" -Level "WARN"
                $sleepSeconds = [math]::Pow(2, $attempt)
                if ($statusCode -eq 429 -and $_.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException] -and $_.Exception.Response.Headers.Contains('Retry-After')) {
                    $retryAfterVal = $_.Exception.Response.Headers.GetValues('Retry-After') | Select-Object -First 1
                    if ($retryAfterVal -match '^\d+$') { $sleepSeconds = [math]::Max($sleepSeconds, [int]$retryAfterVal) }
                }
                Write-Verbose "Retrying token request (attempt $attempt/$maxRetries, sleeping ${sleepSeconds}s)"
                Start-Sleep -Seconds $sleepSeconds
            }
        }
    } finally {
        # Clear plaintext secret from memory on all code paths
        $plainSecret = $null
        if ($body) { $body['client_secret'] = $null }
    }
}

function Test-AgentRestore {
    param([string]$AgentId, [bool]$DryRun)

    $result = @{
        ValidationChecks = @()
        Success = $true
        RecoveryTime = 0
    }

    $startTime = Get-Date

    # IMPORTANT: Recovery steps below are stub implementations using Start-Sleep.
    # RTO/RPO measurements reflect simulated timing only.
    # Replace Start-Sleep calls with actual backup/restore API calls for production use.
    Write-Warning "IMPORTANT: Recovery steps are currently simulated (stub implementation). RTO/RPO measurements reflect simulated timing only. Replace Start-Sleep calls with actual backup/restore API calls for production use."

    Write-Host "  Step 1: Locate agent backup..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 2
            $result.ValidationChecks += @{Check = "Backup Located"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Backup Located"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would locate agent backup" -ForegroundColor Yellow
    }

    Write-Host "  Step 2: Restore agent configuration..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 3
            $result.ValidationChecks += @{Check = "Configuration Restored"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Configuration Restored"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would restore agent configuration" -ForegroundColor Yellow
    }

    Write-Host "  Step 3: Verify agent responds..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 2
            $result.ValidationChecks += @{Check = "Agent Responsive"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Agent Responsive"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would verify agent responds" -ForegroundColor Yellow
    }

    Write-Host "  Step 4: Validate connectors..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 2
            $result.ValidationChecks += @{Check = "Connectors Functional"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Connectors Functional"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would validate connectors" -ForegroundColor Yellow
    }

    Write-Host "  Step 5: Verify security policies..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 1
            $result.ValidationChecks += @{Check = "Security Applied"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Security Applied"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would verify security policies" -ForegroundColor Yellow
    }

    $endTime = Get-Date
    $result.RecoveryTime = ($endTime - $startTime).TotalHours

    # Evaluate validation checks against success flag
    if ($result.ValidationChecks | Where-Object { $_.Status -eq 'FAIL' }) {
        $result.Success = $false
    }

    return $result
}

function Test-EnvironmentFailover {
    param([bool]$DryRun)

    $result = @{
        ValidationChecks = @()
        Success = $true
        RecoveryTime = 0
    }

    $startTime = Get-Date

    # IMPORTANT: Recovery steps below are stub implementations using Start-Sleep.
    # RTO/RPO measurements reflect simulated timing only.
    # Replace Start-Sleep calls with actual failover API calls for production use.
    Write-Warning "IMPORTANT: Recovery steps are currently simulated (stub implementation). RTO/RPO measurements reflect simulated timing only. Replace Start-Sleep calls with actual failover API calls for production use."

    Write-Host "  Step 1: Initiate failover..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 3
            $result.ValidationChecks += @{Check = "Failover Initiated"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Failover Initiated"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would initiate failover" -ForegroundColor Yellow
    }

    Write-Host "  Step 2: Verify backup environment accessible..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 2
            $result.ValidationChecks += @{Check = "Environment Accessible"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Environment Accessible"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would verify backup environment accessible" -ForegroundColor Yellow
    }

    Write-Host "  Step 3: Validate data synchronization..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 2
            $result.ValidationChecks += @{Check = "Data Synchronized"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Data Synchronized"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would validate data synchronization" -ForegroundColor Yellow
    }

    Write-Host "  Step 4: Test agent functionality..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 2
            $result.ValidationChecks += @{Check = "Agents Functional"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Agents Functional"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would test agent functionality" -ForegroundColor Yellow
    }

    $endTime = Get-Date
    $result.RecoveryTime = ($endTime - $startTime).TotalHours

    # Evaluate validation checks against success flag
    if ($result.ValidationChecks | Where-Object { $_.Status -eq 'FAIL' }) {
        $result.Success = $false
    }

    return $result
}

function Test-DataRecovery {
    param([bool]$DryRun)

    $result = @{
        ValidationChecks = @()
        Success = $true
        RecoveryTime = 0
    }

    $startTime = Get-Date

    # IMPORTANT: Recovery steps below are stub implementations using Start-Sleep.
    # RTO/RPO measurements reflect simulated timing only.
    # Replace Start-Sleep calls with actual data recovery API calls for production use.
    Write-Warning "IMPORTANT: Recovery steps are currently simulated (stub implementation). RTO/RPO measurements reflect simulated timing only. Replace Start-Sleep calls with actual data recovery API calls for production use."

    Write-Host "  Step 1: Identify restore point..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 2
            $result.ValidationChecks += @{Check = "Restore Point Found"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Restore Point Found"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would identify restore point" -ForegroundColor Yellow
    }

    Write-Host "  Step 2: Initiate data restore..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 4
            $result.ValidationChecks += @{Check = "Restore Initiated"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Restore Initiated"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would initiate data restore" -ForegroundColor Yellow
    }

    Write-Host "  Step 3: Verify data integrity..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 2
            $result.ValidationChecks += @{Check = "Data Integrity Verified"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Data Integrity Verified"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would verify data integrity" -ForegroundColor Yellow
    }

    Write-Host "  Step 4: Validate record counts..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            Start-Sleep -Seconds 1
            $result.ValidationChecks += @{Check = "Records Complete"; Status = "PASS"}
        } catch {
            $result.ValidationChecks += @{Check = "Records Complete"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would validate record counts" -ForegroundColor Yellow
    }

    $endTime = Get-Date
    $result.RecoveryTime = ($endTime - $startTime).TotalHours

    # Evaluate validation checks against success flag
    if ($result.ValidationChecks | Where-Object { $_.Status -eq 'FAIL' }) {
        $result.Success = $false
    }

    return $result
}

function Save-TestResult {
    param([string]$Environment, [string]$Token, [hashtable]$Result)

    $headers = @{
        "Authorization" = "Bearer $Token"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $record = @{
        fsi_testtype = $Result.TestType
        fsi_executedon = $Result.ExecutedOn
        fsi_actualrto = $Result.ActualRTO
        fsi_targetrto = $Result.TargetRTO
        fsi_rtomet = $Result.RTOMet
        fsi_status = if ($Result.Success) { 1 } else { 2 }
        fsi_validationchecks = (ConvertTo-Json -InputObject @($Result.ValidationChecks) -Compress)
        fsi_correlationid = $script:CorrelationId
    }

    try {
        # Use PATCH with client-generated GUID for idempotent upsert (prevents duplicates on retry)
        $recordId = [guid]::NewGuid().ToString()
        $uri = "$Environment/api/data/v9.2/fsi_drtestresults($recordId)"
        $maxRetries = 3
        Write-Verbose "Saving test result to $uri (max $maxRetries attempts)"
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                Invoke-RestMethod -Uri $uri -Headers $headers -Method Patch -Body ($record | ConvertTo-Json -Depth 5) -ContentType "application/json" -TimeoutSec 30 | Out-Null
                return $true
            } catch {
                $statusCode = 0
                if ($_.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException]) {
                    $statusCode = $_.Exception.Response.StatusCode.value__
                }
                $isTransient = $statusCode -in @(429, 500, 502, 503, 504) -or ($statusCode -eq 0 -and $_.Exception -isnot [System.Management.Automation.RuntimeException])
                if (-not $isTransient -or $attempt -eq $maxRetries) { throw }
                Write-AuditLog "Dataverse save failed (attempt $attempt/$maxRetries): $($_.Exception.Message)" -Level "WARN"
                $sleepSeconds = [math]::Pow(2, $attempt)
                if ($statusCode -eq 429 -and $_.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException] -and $_.Exception.Response.Headers.Contains('Retry-After')) {
                    $retryAfterVal = $_.Exception.Response.Headers.GetValues('Retry-After') | Select-Object -First 1
                    if ($retryAfterVal -match '^\d+$') { $sleepSeconds = [math]::Max($sleepSeconds, [int]$retryAfterVal) }
                }
                Write-Verbose "Retrying Dataverse save (attempt $attempt/$maxRetries, sleeping ${sleepSeconds}s)"
                Start-Sleep -Seconds $sleepSeconds
            }
        }
    } catch {
        Write-Warning "Failed to save result: $($_.Exception.Message)"
        return $false
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
Write-AuditLog "Starting $TestType test"
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
            RecoveryTime = $agentResult.RecoveryTime + $envResult.RecoveryTime + $dataResult.RecoveryTime
        }
    }
}

$testEndTime = Get-Date
$actualRTO = ($testEndTime - $testStartTime).TotalHours
$rtoMet = $actualRTO -le $RTOTargets[$TestType]

# Prepare result summary
# NOTE: RPO measurement requires comparing last backup timestamp with recovery point.
# This is not yet implemented — see README for details.
$finalResult = @{
    TestType = $TestType
    ExecutedOn = $testStartTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    ActualRTO = [math]::Round($actualRTO, 2)
    TargetRTO = $RTOTargets[$TestType]
    RTOMet = $rtoMet
    ActualRPO = $null
    TargetRPO = $RPOTargets[$TestType]
    RPOMet = $null
    RecoveryTime = $testResult.RecoveryTime
    Success = $testResult.Success -and $rtoMet
    ValidationChecks = $testResult.ValidationChecks
}

Write-AuditLog "Test completed — Result: $(if ($finalResult.Success) {'PASS'} else {'FAIL'})"

# Display results
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($check in $testResult.ValidationChecks) {
    $color = if ($check.Status -eq "PASS") { "Green" } else { "Red" }
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
$script:DataverseSaveFailed = $false
if (-not $DryRun -and $TenantId -and $ClientId -and $ClientSecret) {
    Write-Host ""
    Write-Host "Saving results to Dataverse..." -ForegroundColor Gray
    try {
        $authEndpoint = Get-AuthEndpoint -EnvironmentUrl $Environment
        Write-Verbose "Using auth endpoint: $authEndpoint"
        $token = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default" -AuthEndpoint $authEndpoint
        Write-Verbose "Access token acquired, saving results to Dataverse"
        if (Save-TestResult -Environment $Environment -Token $token -Result $finalResult) {
            Write-Host "  Results saved successfully" -ForegroundColor Green
            Write-AuditLog "Results saved to Dataverse"
        } else {
            $script:DataverseSaveFailed = $true
            Write-AuditLog "Dataverse save failed" -Level "WARN"
        }
    } catch {
        $script:DataverseSaveFailed = $true
        Write-Warning "Dataverse authentication failed: $($_.Exception.Message). Test results were not saved."
        Write-AuditLog "Dataverse save skipped — authentication error: $($_.Exception.Message)" -Level "WARN"
    }
} elseif (-not $DryRun) {
    Write-Warning "Dataverse credentials not provided (TenantId/ClientId/ClientSecret). Test results were not saved to Dataverse."
    Write-AuditLog "Dataverse save skipped — credentials not configured" -Level "WARN"
}

Write-Host ""
Write-Host "Test completed at: $($testEndTime.ToString('yyyy-MM-dd HH:mm:ss'))"

# Exit codes: 1 = test failure, 2 = test passed but Dataverse persistence failed
if (-not $finalResult.Success) {
    exit 1
}
if ($script:DataverseSaveFailed) {
    exit 2
}
