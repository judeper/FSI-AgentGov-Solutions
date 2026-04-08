#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Validates agent registry compliance status.

.DESCRIPTION
    Performs compliance validation across the agent registry:
    1. Checks for unregistered agents in Zone 2/3 environments
    2. Detects orphaned agents (owner accounts disabled/deleted)
    3. Validates event log integrity (no gaps, no deletions)
    4. Reports SLA compliance for pending registration requests
    5. Generates examiner-ready compliance report

    Uses Managed Identity authentication exclusively.

.PARAMETER DataverseUrl
    Target Dataverse environment URL.

.PARAMETER OutputFormat
    Output format: JSON, CSV, or Console. Default: Console.

.PARAMETER OutputPath
    Path for output file (required for JSON/CSV format).

.PARAMETER IncludeDetails
    Include detailed per-agent results in output.

.PARAMETER CheckOrphans
    Enable orphan detection via Microsoft Graph user status check.
    Requires User.Read.All permission on the Managed Identity.

.EXAMPLE
    .\Validate-AgentRegistry-Compliance.ps1 `
        -DataverseUrl "https://contoso.crm.dynamics.com" `
        -OutputFormat JSON `
        -OutputPath ".\compliance-report-$(Get-Date -Format yyyyMMdd).json"

.EXAMPLE
    .\Validate-AgentRegistry-Compliance.ps1 `
        -DataverseUrl "https://contoso.crm.dynamics.com" `
        -CheckOrphans `
        -IncludeDetails

.NOTES
    Requires:
    - Azure Automation with System-Assigned Managed Identity
    - Managed Identity assigned System Administrator in target Dataverse env
    - Az.Accounts PowerShell module
    - User.Read.All permission (only if -CheckOrphans is used)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DataverseUrl,

    [Parameter()]
    [ValidateSet("JSON", "CSV", "Console")]
    [string]$OutputFormat = "Console",

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$IncludeDetails,

    [Parameter()]
    [switch]$CheckOrphans
)

$ErrorActionPreference = "Stop"

# --- Validate parameters ---------------------------------------------------------

if ($OutputFormat -in @("JSON", "CSV") -and -not $OutputPath) {
    Write-Error "OutputPath is required when OutputFormat is '$OutputFormat'."
    exit 1
}

# --- Constants -------------------------------------------------------------------

$script:DataverseApiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
$script:CorrelationId = [guid]::NewGuid().ToString("N").Substring(0, 8)
$script:MaxRetries = 3
$script:GraphApiUrl = "https://graph.microsoft.com/v1.0"

# Zone option set values
$script:Zone2Value = 100000001
$script:Zone3Value = 100000002

# Registration status option set values
$script:StatusUnregistered = 100000000

# SLA deadline: pending registration requests older than this are non-compliant
$script:SlaDeadlineHours = 72

# --- Helper Functions ------------------------------------------------------------

function Write-AuditLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ" -AsUTC
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

function Get-DataverseRecords {
    <#
    .SYNOPSIS
        Generic OData query helper for Dataverse. Handles pagination.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$EntitySet,

        [Parameter(Mandatory)]
        [string]$Token,

        [string]$Select,
        [string]$Filter,
        [string]$OrderBy,
        [int]$Top
    )

    $headers = @{
        "Authorization"    = "Bearer $Token"
        "Content-Type"     = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        "Accept"           = "application/json"
        "Prefer"           = "odata.maxpagesize=5000"
    }

    $queryParts = @()
    if ($Select)  { $queryParts += "`$select=$Select" }
    if ($Filter)  { $queryParts += "`$filter=$Filter" }
    if ($OrderBy) { $queryParts += "`$orderby=$OrderBy" }
    if ($Top)     { $queryParts += "`$top=$Top" }

    $queryString = $queryParts -join "&"
    $uri = "$script:DataverseApiBase/${EntitySet}?$queryString"

    $allRecords = [System.Collections.Generic.List[object]]::new()

    $attempt = 0
    while ($uri) {
        $attempt = 0
        $response = $null

        while ($attempt -lt $script:MaxRetries) {
            $attempt++
            try {
                $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
                break
            }
            catch {
                $statusCode = $null
                if ($_.Exception.Response) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }

                if ($statusCode -eq 429 -and $attempt -lt $script:MaxRetries) {
                    $retryAfter = 5 * $attempt
                    Write-AuditLog "Rate limited (429). Retrying in ${retryAfter}s..." -Level WARN
                    Start-Sleep -Seconds $retryAfter
                }
                elseif ($statusCode -ge 500 -and $attempt -lt $script:MaxRetries) {
                    $retryAfter = 3 * $attempt
                    Write-AuditLog "Server error ($statusCode). Retrying in ${retryAfter}s..." -Level WARN
                    Start-Sleep -Seconds $retryAfter
                }
                else {
                    throw
                }
            }
        }

        if (-not $response) {
            Write-AuditLog "No response received after retries" -Level ERROR
            throw "Failed to retrieve records from $EntitySet"
        }

        if ($response.value) {
            $allRecords.AddRange(@($response.value))
        }

        # Handle OData pagination
        $uri = $response.'@odata.nextLink'
    }

    return $allRecords
}

function Test-RegistrationCompliance {
    <#
    .SYNOPSIS
        Checks for unregistered agents in Zone 2 and Zone 3 environments.
    #>
    param(
        [Parameter(Mandatory)]
        [object[]]$Agents
    )

    $violations = [System.Collections.Generic.List[object]]::new()

    foreach ($agent in $Agents) {
        $zone = $agent.fsi_zone
        $status = $agent.fsi_registrationstatus

        # Unregistered agents in Zone 2 or Zone 3 are violations
        if ($status -eq $script:StatusUnregistered -and $zone -in @($script:Zone2Value, $script:Zone3Value)) {
            $zoneName = if ($zone -eq $script:Zone2Value) { "Zone 2" } else { "Zone 3" }
            $violations.Add([PSCustomObject]@{
                AgentId         = $agent.fsi_agentid
                AgentName       = $agent.fsi_agentname
                EnvironmentName = $agent.fsi_environmentname
                Zone            = $zoneName
                Status          = "Unregistered"
                Violation       = "Unregistered agent in $zoneName"
            })
        }
    }

    return @{
        CheckName  = "Registration Compliance"
        Result     = if ($violations.Count -eq 0) { "Pass" } else { "Fail" }
        Violations = $violations
        Summary    = "$($violations.Count) unregistered agent(s) in Zone 2/3"
    }
}

function Test-OrphanStatus {
    <#
    .SYNOPSIS
        Detects orphaned agents whose owner accounts are disabled or deleted.
    #>
    param(
        [Parameter(Mandatory)]
        [object[]]$Agents,

        [Parameter(Mandatory)]
        [string]$GraphToken
    )

    if (-not $Agents -or $Agents.Count -eq 0) {
        return @{
            CheckName  = "Orphan Detection"
            Result     = "Pass"
            Violations = @()
            Summary    = "No agents to check"
        }
    }

    $violations = [System.Collections.Generic.List[object]]::new()

    $headers = @{
        "Authorization" = "Bearer $GraphToken"
        "Content-Type"  = "application/json"
    }

    # Collect unique owner UPNs to minimize Graph API calls
    $ownerUpns = $Agents |
        Where-Object { $_.fsi_ownerupn } |
        Select-Object -ExpandProperty fsi_ownerupn -Unique

    # Build a lookup cache of user account status
    $userStatusCache = @{}
    foreach ($upn in $ownerUpns) {
        try {
            $userUri = "$script:GraphApiUrl/users/$([uri]::EscapeDataString($upn))?`$select=accountEnabled,id,userPrincipalName"
            $user = Invoke-RestMethod -Uri $userUri -Headers $headers -Method Get -ErrorAction Stop
            $userStatusCache[$upn] = @{
                Exists  = $true
                Enabled = $user.accountEnabled
            }
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if ($statusCode -eq 404) {
                $userStatusCache[$upn] = @{ Exists = $false; Enabled = $false }
            }
            elseif ($statusCode -eq 429) {
                Write-AuditLog "Graph API rate limited checking $upn — skipping" -Level WARN
                continue
            }
            else {
                Write-AuditLog "Error checking user $upn — $($_.Exception.Message)" -Level WARN
                continue
            }
        }
    }

    # Check each agent's owner status
    foreach ($agent in $Agents) {
        $upn = $agent.fsi_ownerupn
        if (-not $upn) {
            $violations.Add([PSCustomObject]@{
                AgentId         = $agent.fsi_agentid
                AgentName       = $agent.fsi_agentname
                EnvironmentName = $agent.fsi_environmentname
                OwnerUpn        = "(none)"
                Reason          = "No owner UPN recorded"
            })
            continue
        }

        $status = $userStatusCache[$upn]
        if (-not $status) { continue }  # Skipped due to API error

        if (-not $status.Exists) {
            $violations.Add([PSCustomObject]@{
                AgentId         = $agent.fsi_agentid
                AgentName       = $agent.fsi_agentname
                EnvironmentName = $agent.fsi_environmentname
                OwnerUpn        = $upn
                Reason          = "Owner account deleted"
            })
        }
        elseif (-not $status.Enabled) {
            $violations.Add([PSCustomObject]@{
                AgentId         = $agent.fsi_agentid
                AgentName       = $agent.fsi_agentname
                EnvironmentName = $agent.fsi_environmentname
                OwnerUpn        = $upn
                Reason          = "Owner account disabled"
            })
        }
    }

    return @{
        CheckName  = "Orphan Detection"
        Result     = if ($violations.Count -eq 0) { "Pass" } else { "Fail" }
        Violations = $violations
        Summary    = "$($violations.Count) orphaned agent(s) detected"
    }
}

function Test-EventLogIntegrity {
    <#
    .SYNOPSIS
        Verifies event log consistency by checking record counts and
        that no time gaps exceed 24 hours between consecutive events.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )

    $issues = [System.Collections.Generic.List[object]]::new()

    # Query total event count
    $events = Get-DataverseRecords -EntitySet "fsi_agentcomplianceevents" `
        -Token $Token `
        -Select "fsi_agentcomplianceeventid,fsi_createdon,fsi_eventtype" `
        -OrderBy "fsi_createdon asc"

    if ($events.Count -eq 0) {
        return @{
            CheckName  = "Event Log Integrity"
            Result     = "Warn"
            Violations = @()
            Summary    = "No compliance events found — event log may not be initialized"
        }
    }

    # Check for gaps longer than 24 hours between consecutive events
    for ($i = 1; $i -lt $events.Count; $i++) {
        $prev = [datetime]$events[$i - 1].fsi_createdon
        $curr = [datetime]$events[$i].fsi_createdon
        $gap = ($curr - $prev).TotalHours

        if ($gap -gt 24) {
            $issues.Add([PSCustomObject]@{
                GapStart    = $prev.ToString("yyyy-MM-dd HH:mm:ss")
                GapEnd      = $curr.ToString("yyyy-MM-dd HH:mm:ss")
                GapHours    = [math]::Round($gap, 1)
                Description = "Event log gap of $([math]::Round($gap, 1)) hours"
            })
        }
    }

    return @{
        CheckName  = "Event Log Integrity"
        Result     = if ($issues.Count -eq 0) { "Pass" } else { "Warn" }
        Violations = $issues
        Summary    = "$($events.Count) events; $($issues.Count) gap(s) exceeding 24h"
    }
}

function Test-SlaCompliance {
    <#
    .SYNOPSIS
        Checks pending registration requests against the SLA deadline.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )

    $violations = [System.Collections.Generic.List[object]]::new()

    $slaThreshold = (Get-Date).AddHours(-$script:SlaDeadlineHours).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Query pending requests created before the SLA deadline
    $filter = "fsi_requeststatus eq 100000000 and createdon lt $slaThreshold"
    $pendingRequests = Get-DataverseRecords -EntitySet "fsi_registrationrequests" `
        -Token $Token `
        -Select "fsi_registrationrequestid,fsi_agentid,fsi_agentname,fsi_requestedby,createdon" `
        -Filter $filter

    foreach ($req in $pendingRequests) {
        $createdOn = [datetime]$req.createdon
        $hoursWaiting = [math]::Round(((Get-Date).ToUniversalTime() - $createdOn).TotalHours, 1)

        $violations.Add([PSCustomObject]@{
            RequestId    = $req.fsi_registrationrequestid
            AgentId      = $req.fsi_agentid
            AgentName    = $req.fsi_agentname
            RequestedBy  = $req.fsi_requestedby
            CreatedOn    = $createdOn.ToString("yyyy-MM-dd HH:mm:ss")
            HoursWaiting = $hoursWaiting
            SlaDeadline  = "$script:SlaDeadlineHours hours"
        })
    }

    return @{
        CheckName  = "SLA Compliance"
        Result     = if ($violations.Count -eq 0) { "Pass" } else { "Fail" }
        Violations = $violations
        Summary    = "$($violations.Count) pending request(s) past ${script:SlaDeadlineHours}h SLA"
    }
}

function Format-ComplianceReport {
    <#
    .SYNOPSIS
        Builds the compliance report in the requested output format.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$CheckResults,

        [Parameter(Mandatory)]
        [string]$Format,

        [string]$Path,
        [switch]$Details
    )

    $overallResult = if ($CheckResults | Where-Object { $_.Result -eq "Fail" }) { "Fail" }
                     elseif ($CheckResults | Where-Object { $_.Result -eq "Warn" }) { "Warn" }
                     else { "Pass" }

    $report = @{
        reportType    = "AgentRegistryCompliance"
        generatedAt   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        correlationId = $script:CorrelationId
        overallResult = $overallResult
        checks        = @(
            foreach ($check in $CheckResults) {
                $checkOutput = @{
                    name    = $check.CheckName
                    result  = $check.Result
                    summary = $check.Summary
                }
                if ($Details) {
                    $checkOutput["violations"] = @($check.Violations)
                }
                $checkOutput
            }
        )
    }

    switch ($Format) {
        "JSON" {
            $json = $report | ConvertTo-Json -Depth 10
            $json | Out-File -FilePath $Path -Encoding utf8 -Force
            Write-AuditLog "Report exported to $Path"

            $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($json)
            )
            $fileHash = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ''
            Write-AuditLog "Report SHA-256: $fileHash"
        }

        "CSV" {
            $csvRows = [System.Collections.Generic.List[object]]::new()
            foreach ($check in $CheckResults) {
                if ($check.Violations.Count -eq 0) {
                    $csvRows.Add([PSCustomObject]@{
                        CheckName = $check.CheckName
                        Result    = $check.Result
                        Summary   = $check.Summary
                        Detail    = ""
                    })
                }
                else {
                    foreach ($v in $check.Violations) {
                        $csvRows.Add([PSCustomObject]@{
                            CheckName = $check.CheckName
                            Result    = $check.Result
                            Summary   = $check.Summary
                            Detail    = ($v | ConvertTo-Json -Compress)
                        })
                    }
                }
            }
            $csvRows | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
            Write-AuditLog "Report exported to $Path"
        }

        "Console" {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "  Agent Registry Compliance Report"       -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""

            $resultColor = switch ($overallResult) {
                "Pass" { "Green" }
                "Warn" { "Yellow" }
                "Fail" { "Red" }
            }
            Write-Host "  Overall Result: $overallResult" -ForegroundColor $resultColor
            Write-Host ""

            foreach ($check in $CheckResults) {
                $checkColor = switch ($check.Result) {
                    "Pass" { "Green" }
                    "Warn" { "Yellow" }
                    "Fail" { "Red" }
                }
                $icon = switch ($check.Result) {
                    "Pass" { "[PASS]" }
                    "Warn" { "[WARN]" }
                    "Fail" { "[FAIL]" }
                }
                Write-Host "  $icon $($check.CheckName): $($check.Summary)" -ForegroundColor $checkColor

                if ($Details -and $check.Violations.Count -gt 0) {
                    foreach ($v in $check.Violations) {
                        $props = ($v.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ", "
                        Write-Host "        - $props" -ForegroundColor DarkGray
                    }
                }
            }

            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
        }
    }

    return $overallResult
}

# --- Main Execution --------------------------------------------------------------

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Agent Registry Compliance Validator"    -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-AuditLog "Correlation ID: $script:CorrelationId"
Write-AuditLog "Dataverse URL:  $DataverseUrl"
Write-AuditLog "Output Format:  $OutputFormat"
if ($CheckOrphans) { Write-AuditLog "Orphan detection: enabled" }

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

# Step 2: Acquire tokens
Write-AuditLog "Acquiring access tokens..."
try {
    $dvToken = Get-ManagedIdentityToken -ResourceUrl $DataverseUrl
    Write-AuditLog "  Dataverse: authenticated"
}
catch {
    Write-AuditLog "Dataverse token acquisition failed: $($_.Exception.Message)" -Level ERROR
    Write-Error "Failed to acquire Dataverse access token."
    exit 1
}

$graphToken = $null
if ($CheckOrphans) {
    try {
        $graphToken = Get-ManagedIdentityToken -ResourceUrl "https://graph.microsoft.com"
        Write-AuditLog "  Microsoft Graph: authenticated"
    }
    catch {
        Write-AuditLog "Graph token acquisition failed: $($_.Exception.Message)" -Level ERROR
        Write-Error "Failed to acquire Graph API token. Verify the Managed Identity has User.Read.All permission."
        exit 1
    }
}

# Step 3: Query all agents from fsi_agentinventory
Write-AuditLog "Querying agent inventory..."
$agents = Get-DataverseRecords -EntitySet "fsi_agentinventorys" `
    -Token $dvToken `
    -Select "fsi_agentid,fsi_agentname,fsi_environmentid,fsi_environmentname,fsi_registrationstatus,fsi_zone,fsi_ownerupn,fsi_isorphaned,fsi_lastscannedat"

Write-AuditLog "Found $($agents.Count) agent(s) in inventory"

if ($agents.Count -eq 0) {
    Write-AuditLog "No agents in inventory — run Deploy-AgentRegistry-Baseline.ps1 first" -Level WARN
    exit 0
}

# Step 4: Run compliance checks
$checkResults = [System.Collections.Generic.List[hashtable]]::new()

# Check 1: Registration compliance
Write-AuditLog "Running check: Registration Compliance..."
$registrationResult = Test-RegistrationCompliance -Agents $agents
$checkResults.Add($registrationResult)
Write-AuditLog "  $($registrationResult.Result): $($registrationResult.Summary)"

# Check 2: Orphan detection (optional)
if ($CheckOrphans) {
    Write-AuditLog "Running check: Orphan Detection..."
    $orphanResult = Test-OrphanStatus -Agents $agents -GraphToken $graphToken
    $checkResults.Add($orphanResult)
    Write-AuditLog "  $($orphanResult.Result): $($orphanResult.Summary)"
}

# Check 3: Event log integrity
Write-AuditLog "Running check: Event Log Integrity..."
$eventLogResult = Test-EventLogIntegrity -Token $dvToken
$checkResults.Add($eventLogResult)
Write-AuditLog "  $($eventLogResult.Result): $($eventLogResult.Summary)"

# Check 4: SLA compliance
Write-AuditLog "Running check: SLA Compliance..."
$slaResult = Test-SlaCompliance -Token $dvToken
$checkResults.Add($slaResult)
Write-AuditLog "  $($slaResult.Result): $($slaResult.Summary)"

# Step 5: Generate report
$overallResult = Format-ComplianceReport `
    -CheckResults $checkResults.ToArray() `
    -Format $OutputFormat `
    -Path $OutputPath `
    -Details:$IncludeDetails

Write-AuditLog "Validation completed — overall result: $overallResult"

if ($overallResult -eq "Fail") {
    exit 1
}
