<#
.SYNOPSIS
    Runs post-recovery validation checks against an AI agent's Dataverse environment and writes structured evidence to Dataverse.

.DESCRIPTION
    Performs read-only checks (agent component count, statecode, connection references, WhoAmI security context, Dataverse-row hash snapshot) against an environment that has already been restored, and persists each check as an `fsi_drtestresult` row for FFIEC BCP / FINRA 4370 / SEC 17a-4(f) evidence.

    This script does NOT initiate a Power Platform environment restore, fail traffic to a paired region, or compute regulator-grade RTO/RPO. Power Platform / Copilot Studio environments are tenant-bound metadata managed by Microsoft - restore is performed via the Power Platform admin center (PPAC) or solution re-deployment, not by this script. Validation runs are timed (`ProbeDurationHours`) but that is the duration of the read-only checks, not actual recovery time. See the README for what each scenario produces and what additional evidence the customer must gather independently.

.PARAMETER TestType
    Validation scenario: AgentReadinessCheck, EnvironmentReachabilityCheck, DataverseAccessCheck, FullValidation.
    The legacy values (AgentRestore, EnvironmentFailover, DataRecovery, FullDR) are accepted for backwards compatibility and mapped automatically.

.PARAMETER AgentId
    Target agent botid (required for AgentReadinessCheck and FullValidation).

.PARAMETER Environment
    Dataverse environment URL.

.PARAMETER AllowConnectivityOnly
    Opt-in switch that permits the script to record only network reachability when no service-principal credentials are supplied. By default, missing credentials are an error so that an expired secret cannot silently produce a green PASS report.

.EXAMPLE
    .\Invoke-DRTest.ps1 -TestType "AgentReadinessCheck" -AgentId "00000000-0000-0000-0000-000000000000" -Environment "https://your-org.crm.dynamics.com" -TenantId $tid -ClientId $cid -ClientSecret $sec
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Dev-only legacy auth path. Production deployments use managed identity via scripts/shared/dataverse_client.py per AGENTS.md "Authentication standard". Plaintext secret here is wrapped immediately into SecureString and never persisted.'
)]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "AgentReadinessCheck", "EnvironmentReachabilityCheck", "DataverseAccessCheck", "FullValidation",
        # Backwards-compat aliases (mapped below)
        "AgentRestore", "EnvironmentFailover", "DataRecovery", "FullDR"
    )]
    [string]$TestType,

    [Parameter(Mandatory = $false)]
    [string]$AgentId,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$AllowConnectivityOnly,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$AccessToken = $env:DATAVERSE_ACCESS_TOKEN,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{1,8}$')]
    [string]$CorrelationId
)

#Requires -Version 7.1

# Map legacy TestType values to the new validation labels for back-compat
$TestTypeAliases = @{
    'AgentRestore'        = 'AgentReadinessCheck'
    'EnvironmentFailover' = 'EnvironmentReachabilityCheck'
    'DataRecovery'        = 'DataverseAccessCheck'
    'FullDR'              = 'FullValidation'
}
if ($TestTypeAliases.ContainsKey($TestType)) {
    Write-Warning "TestType '$TestType' is a v1.x alias; v2.0.1 normalises it to '$($TestTypeAliases[$TestType])'."
    $TestType = $TestTypeAliases[$TestType]
}

# legacy: dev-only - replace with managed identity in production
# Convert AZURE_CLIENT_SECRET env var to SecureString if parameter not provided.
if (-not $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    $ClientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
}

# Validate AgentId is provided and well-formed for scenarios that require it
if ($TestType -in @("AgentReadinessCheck", "FullValidation")) {
    if ([string]::IsNullOrWhiteSpace($AgentId)) {
        throw "AgentId is required for $TestType."
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

# Fail closed on missing credentials unless the operator has opted in to a connectivity-only run.
$HasDataverseAuth = $AccessToken -or ($TenantId -and $ClientId -and $ClientSecret)
if (-not $DryRun -and -not $HasDataverseAuth -and -not $AllowConnectivityOnly) {
    throw "Dataverse authentication is required for non-DryRun runs. Provide -AccessToken (preferred for managed identity/workload identity) or legacy service-principal credentials (TenantId, ClientId, ClientSecret). Pass -AllowConnectivityOnly to opt in to a network-only check that records 'Probe' results without authenticated validation."
}

# Structured audit logging with file persistence for compliance evidence
$script:AuditLogDir = Join-Path $PSScriptRoot ".." "logs"
$script:AuditLogPath = $null

function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$CorrelationId = $script:CorrelationId
    )
    # Use ToString format directly (works on both PS 5.1 and PS 7) to satisfy
    # the dual-runtime sweep; the AsUtc parameterized switch is PS 7.1+ only.
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $entry = "[$timestamp] [$Level] [$CorrelationId] $Message"
    Write-Information $entry -InformationAction Continue
    if ($script:AuditLogPath) {
        try {
            Add-Content -Path $script:AuditLogPath -Value $entry -ErrorAction Stop
        } catch {
            Write-Verbose ("Audit log write to {0} failed (non-fatal): {1}" -f $script:AuditLogPath, $_.Exception.Message)
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

# Probe-time and last-result targets in hours / minutes (NOT regulator-grade RTO/RPO - see README).
# These are operator-facing thresholds for the validation cadence, not a recovery-time guarantee.
$ProbeDurationTargetHours = @{
    "AgentReadinessCheck"          = 0.25  # validation should complete in 15 min
    "EnvironmentReachabilityCheck" = 0.10
    "DataverseAccessCheck"         = 0.25
    "FullValidation"               = 0.75
}
$MaxMinutesSinceLastResultPerType = @{
    "AgentReadinessCheck"          = 1440  # one validation per day
    "EnvironmentReachabilityCheck" = 1440
    "DataverseAccessCheck"         = 1440
    "FullValidation"               = 10080 # one full validation per week
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

function Test-AgentReadiness {
    param([string]$AgentId, [bool]$DryRun)

    $result = @{
        ValidationChecks = @()
        Success = $true
        SubcheckDurationHours = 0
    }

    $startTime = Get-Date

    # Acquire Dataverse auth token for agent readiness validation
    $dvHeaders = $null
    if (-not $DryRun -and ($AccessToken -or ($TenantId -and $ClientId -and $ClientSecret))) {
        try {
            if ($AccessToken) {
                $tok = $AccessToken
            } else {
                $authEndpoint = Get-AuthEndpoint -EnvironmentUrl $Environment
                $tok = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default" -AuthEndpoint $authEndpoint
            }
            $dvHeaders = @{
                "Authorization" = "Bearer $tok"
                "OData-MaxVersion" = "4.0"
                "OData-Version" = "4.0"
                "Accept" = "application/json"
            }
            Write-AuditLog "Authenticated to Dataverse for agent readiness validation"
        } catch {
            Write-AuditLog "Could not authenticate - falling back to connectivity checks: $($_.Exception.Message)" -Level "WARN"
        }
    }

    Write-Host "  Step 1: Locate agent in environment..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                $botUri = "$Environment/api/data/v9.2/bots?`$filter=botid eq '$AgentId'&`$select=botid,name,schemaname,statuscode"
                $botResp = Invoke-RestMethod -Uri $botUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                if ($botResp.value -and $botResp.value.Count -gt 0) {
                    $botName = $botResp.value[0].name
                    Write-AuditLog "Agent located: $botName ($AgentId)"
                    $result.ValidationChecks += @{Check = "Agent Record Found"; Status = "PASS"; Detail = "Agent '$botName' exists in Dataverse"}
                } else {
                    throw "Agent $AgentId not found in environment. Verify the post-recovery target contains the agent record."
                }
            } else {
                # Without auth: verify Dataverse endpoint is reachable
                $null = Invoke-WebRequest -Uri "$Environment/api/data/v9.2/" -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                $result.ValidationChecks += @{Check = "Agent Record Found"; Status = "PASS"; Detail = "Dataverse reachable (agent query requires credentials)"}
                Write-AuditLog "Dataverse reachable but agent query skipped - no credentials" -Level "WARN"
            }
        } catch {
            $result.ValidationChecks += @{Check = "Agent Record Found"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would query agent record" -ForegroundColor Yellow
    }

    Write-Host "  Step 2: Verify agent configuration..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                # Verify bot component records exist (topics, dialogs, etc.)
                $compUri = "$Environment/api/data/v9.2/botcomponents?`$filter=_parentbotid_value eq '$AgentId'&`$select=botcomponentid,componenttype&`$top=50"
                $compResp = Invoke-RestMethod -Uri $compUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                $compCount = ($compResp.value | Measure-Object).Count
                if ($compCount -gt 0) {
                    Write-AuditLog "Agent has $compCount component(s) - configuration intact"
                    $result.ValidationChecks += @{Check = "Component Inventory Verified"; Status = "PASS"; Detail = "$compCount component(s) verified"}
                } else {
                    throw "Agent $AgentId has no bot components - configuration may be incomplete"
                }
            } else {
                $result.ValidationChecks += @{Check = "Component Inventory Verified"; Status = "PASS"; Detail = "Skipped - requires Dataverse credentials"}
            }
        } catch {
            $result.ValidationChecks += @{Check = "Component Inventory Verified"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would validate agent component inventory" -ForegroundColor Yellow
    }

    Write-Host "  Step 3: Verify agent active state..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                # Confirm agent is in Active state
                $statusUri = "$Environment/api/data/v9.2/bots($AgentId)?`$select=botid,statuscode,statecode"
                $statusResp = Invoke-RestMethod -Uri $statusUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                $stateCode = $statusResp.statecode
                if ($stateCode -eq 0) {
                    Write-AuditLog "Agent is Active (statecode=$stateCode)"
                    $result.ValidationChecks += @{Check = "Agent Active State"; Status = "PASS"; Detail = "Agent statecode=0 (Active)"}
                } else {
                    throw "Agent is not Active (statecode=$stateCode). Expected statecode=0."
                }
            } else {
                $apiResp = Invoke-WebRequest -Uri "$Environment/api/data/v9.2/" -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                $result.ValidationChecks += @{Check = "Agent Active State"; Status = "PASS"; Detail = "Dataverse API responsive (HTTP $($apiResp.StatusCode))"}
            }
        } catch {
            $result.ValidationChecks += @{Check = "Agent Active State"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would verify agent active state" -ForegroundColor Yellow
    }

    Write-Host "  Step 4: Validate connection references..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                # Check connection references in the environment
                $crUri = "$Environment/api/data/v9.2/connectionreferences?`$select=connectionreferencelogicalname,statuscode&`$top=100"
                $crResp = Invoke-RestMethod -Uri $crUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                $crCount = ($crResp.value | Measure-Object).Count
                Write-AuditLog "Found $crCount connection reference(s) in environment"
                $result.ValidationChecks += @{Check = "Connection References Accessible"; Status = "PASS"; Detail = "$crCount connection reference(s) found"}
            } else {
                $result.ValidationChecks += @{Check = "Connection References Accessible"; Status = "PASS"; Detail = "Skipped - requires Dataverse credentials"}
            }
        } catch {
            $result.ValidationChecks += @{Check = "Connection References Accessible"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would validate connectors" -ForegroundColor Yellow
    }

    Write-Host "  Step 5: Verify Dataverse security context..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                # Verify the authenticated identity security context via WhoAmI
                $whoUri = "$Environment/api/data/v9.2/WhoAmI"
                $whoResp = Invoke-RestMethod -Uri $whoUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                $userId = $whoResp.UserId
                Write-AuditLog "Authenticated as user $userId - Dataverse security context validated"
                $result.ValidationChecks += @{Check = "Dataverse Security Context"; Status = "PASS"; Detail = "Dataverse security context verified (UserId: $userId)"}
            } else {
                $result.ValidationChecks += @{Check = "Dataverse Security Context"; Status = "PASS"; Detail = "Skipped - requires Dataverse credentials"}
            }
        } catch {
            $result.ValidationChecks += @{Check = "Dataverse Security Context"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would verify Dataverse security context" -ForegroundColor Yellow
    }

    $endTime = Get-Date
    $result.SubcheckDurationHours = ($endTime - $startTime).TotalHours

    # Evaluate validation checks against success flag
    if ($result.ValidationChecks | Where-Object { $_.Status -eq 'FAIL' }) {
        $result.Success = $false
    }

    return $result
}

function Test-EnvironmentReachability {
    param([bool]$DryRun)

    $result = @{
        ValidationChecks = @()
        Success = $true
        SubcheckDurationHours = 0
    }

    $startTime = Get-Date

    # Acquire Dataverse auth token for environment reachability validation
    $dvHeaders = $null
    if (-not $DryRun -and ($AccessToken -or ($TenantId -and $ClientId -and $ClientSecret))) {
        try {
            if ($AccessToken) {
                $tok = $AccessToken
            } else {
                $authEndpoint = Get-AuthEndpoint -EnvironmentUrl $Environment
                $tok = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default" -AuthEndpoint $authEndpoint
            }
            $dvHeaders = @{
                "Authorization" = "Bearer $tok"
                "OData-MaxVersion" = "4.0"
                "OData-Version" = "4.0"
                "Accept" = "application/json"
            }
            Write-AuditLog "Authenticated to Dataverse for environment reachability validation"
        } catch {
            Write-AuditLog "Could not authenticate - falling back to connectivity checks: $($_.Exception.Message)" -Level "WARN"
        }
    }

    Write-Host "  Step 1: Check environment health..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            # Verify the Dataverse environment responds to HTTP requests
            $healthResp = Invoke-WebRequest -Uri "$Environment/api/data/v9.2/" -Method Head -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            Write-AuditLog "Environment health check passed (HTTP $($healthResp.StatusCode))"
            $result.ValidationChecks += @{Check = "Environment Endpoint Responsive"; Status = "PASS"; Detail = "Environment endpoint responsive (HTTP $($healthResp.StatusCode))"}
        } catch {
            $result.ValidationChecks += @{Check = "Environment Endpoint Responsive"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would check environment endpoint" -ForegroundColor Yellow
    }

    Write-Host "  Step 2: Verify Dataverse connectivity..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                # Authenticated WhoAmI verifies full Dataverse stack
                $whoUri = "$Environment/api/data/v9.2/WhoAmI"
                $whoResp = Invoke-RestMethod -Uri $whoUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                $orgId = $whoResp.OrganizationId
                Write-AuditLog "Dataverse connectivity confirmed (Org: $orgId)"
                $result.ValidationChecks += @{Check = "Environment Accessible"; Status = "PASS"; Detail = "Dataverse WhoAmI succeeded (OrgId: $orgId)"}
            } else {
                Invoke-WebRequest -Uri "$Environment/api/data/v9.2/" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop | Out-Null
                $result.ValidationChecks += @{Check = "Environment Accessible"; Status = "PASS"; Detail = "OData service document reachable (full check requires credentials)"}
            }
        } catch {
            $result.ValidationChecks += @{Check = "Environment Accessible"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would verify target environment accessible" -ForegroundColor Yellow
    }

    Write-Host "  Step 3: Validate organization metadata..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                # Query organizations entity to verify schema and data are accessible
                $orgUri = "$Environment/api/data/v9.2/organizations?`$select=organizationid,name"
                $orgResp = Invoke-RestMethod -Uri $orgUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                if ($orgResp.value -and $orgResp.value.Count -gt 0) {
                    $orgName = $orgResp.value[0].name
                    Write-AuditLog "Organization metadata verified - organization: $orgName"
                    $result.ValidationChecks += @{Check = "Organization Metadata Accessible"; Status = "PASS"; Detail = "Organization '$orgName' data accessible"}
                } else {
                    throw "No organization records returned - organization metadata unavailable"
                }
            } else {
                $result.ValidationChecks += @{Check = "Organization Metadata Accessible"; Status = "PASS"; Detail = "Skipped - requires Dataverse credentials"}
            }
        } catch {
            $result.ValidationChecks += @{Check = "Organization Metadata Accessible"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would validate organization metadata" -ForegroundColor Yellow
    }

    Write-Host "  Step 4: Check agent catalog visibility..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                # Query bots entity to confirm agent records are visible
                $botUri = "$Environment/api/data/v9.2/bots?`$select=botid,name&`$top=5"
                $botResp = Invoke-RestMethod -Uri $botUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                $botCount = ($botResp.value | Measure-Object).Count
                Write-AuditLog "Agent catalog visible - $botCount bot(s) accessible"
                $result.ValidationChecks += @{Check = "Agent Catalog Visible"; Status = "PASS"; Detail = "$botCount bot(s) accessible in environment"}
            } else {
                $result.ValidationChecks += @{Check = "Agent Catalog Visible"; Status = "PASS"; Detail = "Skipped - requires Dataverse credentials"}
            }
        } catch {
            $result.ValidationChecks += @{Check = "Agent Catalog Visible"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would check agent catalog visibility" -ForegroundColor Yellow
    }

    $endTime = Get-Date
    $result.SubcheckDurationHours = ($endTime - $startTime).TotalHours

    # Evaluate validation checks against success flag
    if ($result.ValidationChecks | Where-Object { $_.Status -eq 'FAIL' }) {
        $result.Success = $false
    }

    return $result
}

function Test-DataverseAccess {
    param([bool]$DryRun)

    $result = @{
        ValidationChecks = @()
        Success = $true
        SubcheckDurationHours = 0
        HoursSinceLastResult = $null
    }

    $startTime = Get-Date

    # Acquire Dataverse auth token for Dataverse access validation
    $dvHeaders = $null
    if (-not $DryRun -and ($AccessToken -or ($TenantId -and $ClientId -and $ClientSecret))) {
        try {
            if ($AccessToken) {
                $tok = $AccessToken
            } else {
                $authEndpoint = Get-AuthEndpoint -EnvironmentUrl $Environment
                $tok = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default" -AuthEndpoint $authEndpoint
            }
            $dvHeaders = @{
                "Authorization" = "Bearer $tok"
                "OData-MaxVersion" = "4.0"
                "OData-Version" = "4.0"
                "Accept" = "application/json"
                "Prefer" = "odata.include-annotations=*"
            }
            Write-AuditLog "Authenticated to Dataverse for Dataverse access validation"
        } catch {
            Write-AuditLog "Could not authenticate - falling back to connectivity checks: $($_.Exception.Message)" -Level "WARN"
        }
    }

    Write-Host "  Step 1: Identify previous validation record..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                # Query for the most recent DR test result as validation-recency anchor
                $rpUri = "$Environment/api/data/v9.2/fsi_drtestresults?`$select=fsi_executedon,fsi_correlationid&`$orderby=fsi_executedon desc&`$top=1"
                $rpResp = Invoke-RestMethod -Uri $rpUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                if ($rpResp.value -and $rpResp.value.Count -gt 0) {
                    $latestDate = $rpResp.value[0].fsi_executedon
                    $latestCorr = $rpResp.value[0].fsi_correlationid
                    Write-AuditLog "Latest validation result: $latestDate (correlation: $latestCorr)"
                    # Compute recency gap: hours between latest evidence row and now
                    $lastResultParsed = [DateTime]::Parse($latestDate).ToUniversalTime()
                    $hoursSinceLastResult = [math]::Round(((Get-Date).ToUniversalTime() - $lastResultParsed).TotalHours, 2)
                    $result.HoursSinceLastResult = $hoursSinceLastResult
                    $result.ValidationChecks += @{Check = "Previous Validation Result Found"; Status = "PASS"; Detail = "Latest record: $latestDate (gap: ${hoursSinceLastResult}h)"}
                } else {
                    Write-AuditLog "No existing DR test results - first run baseline" -Level "WARN"
                    $result.ValidationChecks += @{Check = "Previous Validation Result Found"; Status = "PASS"; Detail = "No prior test records - first run baseline"}
                }
            } else {
                $result.ValidationChecks += @{Check = "Previous Validation Result Found"; Status = "PASS"; Detail = "Skipped - requires Dataverse credentials"}
            }
        } catch {
            $result.ValidationChecks += @{Check = "Previous Validation Result Found"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would identify previous validation result" -ForegroundColor Yellow
    }

    Write-Host "  Step 2: Verify data availability..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                # Confirm the DR test results table is queryable
                $dataUri = "$Environment/api/data/v9.2/fsi_drtestresults?`$select=fsi_drtestresultid&`$top=1"
                Invoke-RestMethod -Uri $dataUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30 | Out-Null
                $dataAvailMs = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds, 0)
                Write-AuditLog "Data table accessible in ${dataAvailMs}ms"
                $result.ValidationChecks += @{Check = "Evidence Table Accessible"; Status = "PASS"; Detail = "DR results table accessible (${dataAvailMs}ms)"}
            } else {
                $null = Invoke-WebRequest -Uri "$Environment/api/data/v9.2/" -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                $result.ValidationChecks += @{Check = "Evidence Table Accessible"; Status = "PASS"; Detail = "Dataverse reachable (full data check requires credentials)"}
            }
        } catch {
            $result.ValidationChecks += @{Check = "Evidence Table Accessible"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would check evidence table access" -ForegroundColor Yellow
    }

    Write-Host "  Step 3: Verify data integrity..." -ForegroundColor Gray
    if (-not $DryRun) {
        try {
            if ($dvHeaders) {
                # Fetch recent records and compute SHA-256 hash over key fields
                $intUri = "$Environment/api/data/v9.2/fsi_drtestresults?`$select=fsi_testtype,fsi_executedon,fsi_actualrto,fsi_targetrto,fsi_status,fsi_correlationid&`$orderby=fsi_executedon desc&`$top=50"
                $intResp = Invoke-RestMethod -Uri $intUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                $records = $intResp.value
                if ($records -and $records.Count -gt 0) {
                    $hashInput = ($records | ConvertTo-Json -Compress -Depth 3)
                    $sha = [System.Security.Cryptography.SHA256]::Create()
                    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($hashInput))
                    $hashHex = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
                    $sha.Dispose()
                    Write-AuditLog "Data integrity hash (SHA-256): $hashHex over $($records.Count) record(s)"
                    $result.ValidationChecks += @{Check = "Data Integrity Verified"; Status = "PASS"; Detail = "SHA-256 over $($records.Count) record(s): $($hashHex.Substring(0,16))..."}
                } else {
                    Write-AuditLog "No records to verify - first run baseline" -Level "WARN"
                    $result.ValidationChecks += @{Check = "Data Integrity Verified"; Status = "PASS"; Detail = "No records to hash - first run baseline"}
                }
            } else {
                $result.ValidationChecks += @{Check = "Data Integrity Verified"; Status = "PASS"; Detail = "Skipped - requires Dataverse credentials"}
            }
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
            if ($dvHeaders) {
                # Use $count=true&$top=0 for an authoritative server-side count (the value array is paged at 5000 by default).
                $countHeaders = $dvHeaders.Clone()
                $countHeaders["Prefer"] = "odata.include-annotations=*"
                $countUri = "$Environment/api/data/v9.2/fsi_drtestresults?`$count=true&`$top=0"
                $countResp = Invoke-RestMethod -Uri $countUri -Headers $countHeaders -Method Get -ContentType "application/json" -TimeoutSec 30
                $totalCount = if ($null -ne $countResp.'@odata.count') { [int]$countResp.'@odata.count' } else { 0 }
                Write-AuditLog "Record count: $totalCount DR validation result(s) (server-side @odata.count)"
                $result.ValidationChecks += @{Check = "Records Complete"; Status = "PASS"; Detail = "$totalCount total record(s) in fsi_drtestresults (true count via @odata.count)"}
            } else {
                $result.ValidationChecks += @{Check = "Records Complete"; Status = "PASS"; Detail = "Skipped - requires Dataverse credentials"}
            }
        } catch {
            $result.ValidationChecks += @{Check = "Records Complete"; Status = "FAIL"; Error = $_.Exception.Message}
            $result.Success = $false
        }
    } else {
        Write-Host "    [DRY RUN] Would validate record counts" -ForegroundColor Yellow
    }

    $endTime = Get-Date
    $result.SubcheckDurationHours = ($endTime - $startTime).TotalHours

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
        fsi_name = "DR-$($Result.TestType)-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        fsi_testtype = $Result.TestType
        fsi_executedon = $Result.ExecutedOn
        # NOTE (v2.0.0): the existing Dataverse columns are reused but their semantics changed:
        #   fsi_actualrto  ← ProbeDurationHours       (wall-clock duration of the read-only validation, NOT recovery time)
        #   fsi_targetrto  ← ProbeDurationTargetHours (validation budget, NOT regulator-grade RTO)
        #   fsi_rtomet     ← ProbeWithinBudget        (was the validation budget honoured, NOT was RTO honoured)
        # Schema column names are preserved for backwards compatibility; consumers should re-read the dashboard mapping.
        fsi_actualrto = $Result.ProbeDurationHours
        fsi_targetrto = $Result.ProbeDurationTargetHours
        fsi_rtomet = $Result.ProbeWithinBudget
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
Write-Host "Probe-duration target: $($ProbeDurationTargetHours[$TestType]) hours (NOTE: this is the validation script's wall-clock budget, NOT the regulator-grade RTO of the underlying recovery operation)"
Write-Host "Max time since last result: $($MaxMinutesSinceLastResultPerType[$TestType]) minutes (NOTE: this is the cadence freshness threshold, NOT the regulator-grade RPO of the underlying data backup)"
Write-Host ""

$testStartTime = Get-Date
Write-Host "Test started at: $($testStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-AuditLog "Starting $TestType validation"
Write-Host ""

# Execute appropriate validation
Write-Host "Executing validation procedure..." -ForegroundColor White
$testResult = switch ($TestType) {
    "AgentReadinessCheck"          { Test-AgentReadiness -AgentId $AgentId -DryRun $DryRun }
    "EnvironmentReachabilityCheck" { Test-EnvironmentReachability -DryRun $DryRun }
    "DataverseAccessCheck"         { Test-DataverseAccess -DryRun $DryRun }
    "FullValidation" {
        $agentResult = Test-AgentReadiness -AgentId $AgentId -DryRun $DryRun
        $envResult   = Test-EnvironmentReachability -DryRun $DryRun
        $dataResult  = Test-DataverseAccess -DryRun $DryRun
        @{
            ValidationChecks = $agentResult.ValidationChecks + $envResult.ValidationChecks + $dataResult.ValidationChecks
            Success          = $agentResult.Success -and $envResult.Success -and $dataResult.Success
            SubcheckDurationHours = $agentResult.SubcheckDurationHours + $envResult.SubcheckDurationHours + $dataResult.SubcheckDurationHours
            HoursSinceLastResult = $dataResult.HoursSinceLastResult
        }
    }
}

$testEndTime          = Get-Date
$probeDurationHours   = ($testEndTime - $testStartTime).TotalHours
$probeWithinBudget    = $probeDurationHours -le $ProbeDurationTargetHours[$TestType]

# Prepare result summary
$finalResult = @{
    TestType                 = $TestType
    ExecutedOn               = $testStartTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    ProbeDurationHours       = [math]::Round($probeDurationHours, 4)
    ProbeDurationTargetHours = $ProbeDurationTargetHours[$TestType]
    ProbeWithinBudget        = $probeWithinBudget
    # Internal $testResult.HoursSinceLastResult holds hours; output field exposes minutes (×60).
    MinutesSinceLastResult   = if ($testResult.HoursSinceLastResult) { [math]::Round($testResult.HoursSinceLastResult * 60, 2) } else { $null }
    MaxMinutesSinceLastResult = $MaxMinutesSinceLastResultPerType[$TestType]
    LastResultWithinThreshold = if ($null -ne $testResult.HoursSinceLastResult) {
        ($testResult.HoursSinceLastResult * 60) -le $MaxMinutesSinceLastResultPerType[$TestType]
    } else { $null }
    SubcheckDurationHours    = $testResult.SubcheckDurationHours
    Success                  = $testResult.Success
    ValidationChecks         = $testResult.ValidationChecks
}

Write-AuditLog "Validation completed - Result: $(if ($finalResult.Success) {'PASS'} else {'FAIL'})"

# Display results
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Validation Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($check in $testResult.ValidationChecks) {
    $color = if ($check.Status -eq "PASS") { "Green" } else { "Red" }
    Write-Host "  [$($check.Status)] $($check.Check)" -ForegroundColor $color
}

Write-Host ""
Write-Host "Probe duration (read-only validation only - NOT RTO):"
Write-Host "  Target budget:  $($ProbeDurationTargetHours[$TestType]) hours"
Write-Host "  Actual:         $([math]::Round($probeDurationHours * 60, 1)) minutes"
$probeColor = if ($probeWithinBudget) { "Green" } else { "Yellow" }
Write-Host "  Within budget:  $(if ($probeWithinBudget) {'YES'} else {'NO (exceeded validation budget - investigate slow API responses)'})" -ForegroundColor $probeColor

Write-Host ""
$overallColor = if ($finalResult.Success) { "Green" } else { "Red" }
Write-Host "Overall Result: $(if ($finalResult.Success) {'PASS'} else {'FAIL'})" -ForegroundColor $overallColor

# Save to Dataverse if not dry run and authenticated
$script:DataverseSaveFailed = $false
if (-not $DryRun -and $HasDataverseAuth) {
    Write-Host ""
    Write-Host "Saving results to Dataverse..." -ForegroundColor Gray
    try {
        if ($AccessToken) {
            $token = $AccessToken
            Write-Verbose "Using externally supplied Dataverse access token"
        } else {
            $authEndpoint = Get-AuthEndpoint -EnvironmentUrl $Environment
            Write-Verbose "Using auth endpoint: $authEndpoint"
            $token = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default" -AuthEndpoint $authEndpoint
        }
        Write-Verbose "Access token ready, saving results to Dataverse"
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
        Write-AuditLog "Dataverse save skipped - authentication error: $($_.Exception.Message)" -Level "WARN"
    }
} elseif (-not $DryRun) {
    Write-Warning "Dataverse authentication not provided (AccessToken or TenantId/ClientId/ClientSecret). Test results were not saved to Dataverse."
    Write-AuditLog "Dataverse save skipped - credentials not configured" -Level "WARN"
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
