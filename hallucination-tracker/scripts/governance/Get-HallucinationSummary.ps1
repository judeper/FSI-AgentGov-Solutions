#Requires -Version 7.0
#Requires -Modules MSAL.PS

<#
.SYNOPSIS
    Generates a dashboard-style summary of hallucination patterns for governance review.

.DESCRIPTION
    Queries hallucination report data from Dataverse and computes governance
    metrics including category distribution, severity breakdown, source analysis,
    top offending agents, weekly trends, and pattern clusters.

    Produces an overall health status (Healthy, Warning, Critical) based on
    cluster thresholds and severity patterns.

    This script supports FSI-AgentGov Controls:
    - 3.10 (Hallucination Feedback Loop) — pattern analysis and reporting
    - 2.9 (Performance Monitoring) — agent quality metrics
    - 2.12 (Supervision) — supervisory oversight dashboard

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID for authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for service principal authentication.

.PARAMETER ClientSecret
    Client secret for service principal authentication.

.PARAMETER DaysBack
    Number of days of history to analyze. Default: 30.

.PARAMETER OutputFormat
    Output format: Table (console display), JSON (machine-readable), or Object (pipeline).
    Default: Table.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.EXAMPLE
    .\Get-HallucinationSummary.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Interactive

    Displays a 30-day hallucination summary table using interactive authentication.

.EXAMPLE
    .\Get-HallucinationSummary.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -DaysBack 90 `
        -OutputFormat JSON `
        -ClientId "12345..." `
        -ClientSecret (ConvertTo-SecureString "secret" -AsPlainText -Force)

    Exports 90-day hallucination summary as JSON using service principal.

.EXAMPLE
    $summary = .\Get-HallucinationSummary.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputFormat Object `
        -Interactive

    Returns summary as a PSCustomObject for pipeline consumption.

.OUTPUTS
    Depends on OutputFormat:
    - Table: Formatted console output (no pipeline object)
    - JSON: JSON string
    - Object: PSCustomObject with OverallStatus, Metrics, Distributions, TopAgents, Trends, Patterns

.NOTES
    Version: 1.0.0
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module for Dataverse authentication
    - Hallucination Tracker Dataverse schema deployed (fsi_hallucinationreports table)

    Overall status logic:
    - Healthy: No critical-severity clusters and no agent exceeds threshold
    - Warning: Medium-severity clusters detected or agent approaching threshold
    - Critical: Critical-severity clusters detected or agent exceeds report threshold
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$DaysBack = 30,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [switch]$Interactive
)

$ErrorActionPreference = "Stop"

#region Option Set Mappings

$CategoryMap = @{
    100000000 = 'Factual Error'
    100000001 = 'Fabricated Data'
    100000002 = 'Citation Missing'
    100000003 = 'Outdated Info'
    100000004 = 'Confidence Overstatement'
}

$SeverityMap = @{
    100000000 = 'Low'
    100000001 = 'Medium'
    100000002 = 'High'
    100000003 = 'Critical'
}

$SourceMap = @{
    100000000 = 'User'
    100000001 = 'Supervisor'
    100000002 = 'Automated'
    100000003 = 'Customer'
}

# Thresholds for pattern detection
$ClusterThreshold = 3
$AgentReportThreshold = 5

#endregion

#region Initialization

if ($OutputFormat -eq 'Table') {
    Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Hallucination Summary Dashboard                ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  FSI-AgentGov Hallucination Feedback Tracker     ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

#endregion

#region Authentication

if ($OutputFormat -eq 'Table') {
    Write-Host "Authenticating to Dataverse..." -ForegroundColor Cyan
}

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

if ($Interactive) {
    try {
        if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
            throw "MSAL.PS module is required for authentication. Install with: Install-Module MSAL.PS -Scope CurrentUser"
        }
        Import-Module MSAL.PS -ErrorAction Stop

        $msalParams = @{
            TenantId    = $TenantId
            Scopes      = @($dataverseScope)
            Interactive = $true
        }

        if ($ClientId) {
            $msalParams.ClientId = $ClientId
        }

        $authResult = Get-MsalToken @msalParams
        $accessToken = $authResult.AccessToken
    }
    catch {
        Write-Error "Interactive authentication failed: $($_.Exception.Message)"
        throw
    }
}
else {
    if (-not $ClientId) {
        throw "ClientId is required for service principal authentication. Use -Interactive for browser-based auth."
    }
    if (-not $ClientSecret) {
        throw "ClientSecret is required for service principal authentication."
    }
    if (-not $TenantId) {
        throw "TenantId is required for service principal authentication."
    }

    try {
        if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
            throw "MSAL.PS module is required for authentication. Install with: Install-Module MSAL.PS -Scope CurrentUser"
        }
        Import-Module MSAL.PS -ErrorAction Stop

        $authResult = Get-MsalToken `
            -TenantId $TenantId `
            -ClientId $ClientId `
            -ClientSecret $ClientSecret `
            -Scopes @($dataverseScope)

        $accessToken = $authResult.AccessToken
    }
    catch {
        Write-Error "Service principal authentication failed: $($_.Exception.Message)"
        throw
    }
}

if ($OutputFormat -eq 'Table') {
    Write-Host "Authentication successful." -ForegroundColor Green
    Write-Host ""
}

#endregion

#region Query Hallucination Reports

if ($OutputFormat -eq 'Table') {
    Write-Host "Querying hallucination reports ($DaysBack days)..." -ForegroundColor Cyan
}

$fromDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
$headers = @{
    Authorization   = "Bearer $accessToken"
    Accept          = "application/json"
    "OData-Version" = "4.0"
    Prefer          = "odata.maxpagesize=5000"
}

$filter = "createdon ge $fromDate"
$select = "fsi_hallucinationreportid,fsi_category,fsi_severity,fsi_agentid,fsi_description,fsi_source,fsi_isresolved,createdon,modifiedon"

$queryUrl = "$apiBase/fsi_hallucinationreports?`$select=$select&`$filter=$filter&`$orderby=createdon desc"

$allReports = @()

try {
    $nextLink = $queryUrl

    while ($nextLink) {
        $response = Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get
        $allReports += $response.value
        $nextLink = $response.'@odata.nextLink'
    }

    if ($OutputFormat -eq 'Table') {
        Write-Host "Retrieved $($allReports.Count) report(s)" -ForegroundColor Green
        Write-Host ""
    }
}
catch {
    Write-Error "Failed to query hallucination reports: $($_.Exception.Message)"
    throw
}

#endregion

#region Compute Metrics

# Map raw records
$reports = $allReports | ForEach-Object {
    [PSCustomObject]@{
        reportId   = $_.fsi_hallucinationreportid
        category   = if ($null -ne $_.fsi_category) { $CategoryMap[[int]$_.fsi_category] } else { 'Unknown' }
        severity   = if ($null -ne $_.fsi_severity) { $SeverityMap[[int]$_.fsi_severity] } else { 'Unknown' }
        agentId    = $_.fsi_agentid
        source     = if ($null -ne $_.fsi_source) { $SourceMap[[int]$_.fsi_source] } else { 'Unknown' }
        isResolved = $_.fsi_isresolved
        createdOn  = $_.createdon
        modifiedOn = $_.modifiedon
    }
}

$totalReports = $reports.Count

# Resolved vs unresolved based on the fsi_isresolved flag
$resolvedCount = 0
$unresolvedCount = 0
foreach ($report in $reports) {
    if ($report.isResolved -eq $true) {
        $resolvedCount++
    }
    else {
        $unresolvedCount++
    }
}

# Category distribution
$categoryDistribution = @{}
foreach ($report in $reports) {
    $cat = $report.category
    if (-not $categoryDistribution.ContainsKey($cat)) { $categoryDistribution[$cat] = 0 }
    $categoryDistribution[$cat]++
}

# Severity distribution
$severityDistribution = @{}
foreach ($report in $reports) {
    $sev = $report.severity
    if (-not $severityDistribution.ContainsKey($sev)) { $severityDistribution[$sev] = 0 }
    $severityDistribution[$sev]++
}

# Source distribution
$sourceDistribution = @{}
foreach ($report in $reports) {
    $src = $report.source
    if (-not $sourceDistribution.ContainsKey($src)) { $sourceDistribution[$src] = 0 }
    $sourceDistribution[$src]++
}

# Top 5 agents by report count with hallucination rate
$agentCounts = @{}
foreach ($report in $reports) {
    $agent = if ($report.agentId) { $report.agentId } else { '(unspecified)' }
    if (-not $agentCounts.ContainsKey($agent)) { $agentCounts[$agent] = 0 }
    $agentCounts[$agent]++
}

$topAgents = $agentCounts.GetEnumerator() |
    Sort-Object -Property Value -Descending |
    Select-Object -First 5 |
    ForEach-Object {
        $rate = if ($totalReports -gt 0) { [math]::Round(($_.Value / $totalReports) * 100, 1) } else { 0 }
        [PSCustomObject]@{
            AgentId           = $_.Key
            ReportCount       = $_.Value
            HallucinationRate = "$rate%"
        }
    }

# Weekly trend
$weeklyTrend = @{}
foreach ($report in $reports) {
    if ($report.createdOn) {
        $date = [datetime]$report.createdOn
        # ISO week start (Monday)
        $weekStart = $date.AddDays(-([int]$date.DayOfWeek + 6) % 7).ToString("yyyy-MM-dd")
        if (-not $weeklyTrend.ContainsKey($weekStart)) { $weeklyTrend[$weekStart] = 0 }
        $weeklyTrend[$weekStart]++
    }
}

$trendSorted = $weeklyTrend.GetEnumerator() |
    Sort-Object -Property Key |
    ForEach-Object {
        [PSCustomObject]@{
            WeekStarting = $_.Key
            ReportCount  = $_.Value
        }
    }

# Pattern detection: categories with count >= cluster threshold
$patterns = $categoryDistribution.GetEnumerator() |
    Where-Object { $_.Value -ge $ClusterThreshold } |
    ForEach-Object {
        [PSCustomObject]@{
            Category = $_.Key
            Count    = $_.Value
            Status   = "Cluster Detected"
        }
    }

# Overall status determination
$overallStatus = "Healthy"

# Check for critical-severity clusters
$criticalCount = if ($severityDistribution.ContainsKey('Critical')) { $severityDistribution['Critical'] } else { 0 }
$highCount = if ($severityDistribution.ContainsKey('High')) { $severityDistribution['High'] } else { 0 }

$hasCriticalCluster = $criticalCount -ge $ClusterThreshold
$hasAgentThresholdExceeded = ($agentCounts.Values | Where-Object { $_ -ge $AgentReportThreshold }).Count -gt 0
$hasMediumCluster = ($patterns | Measure-Object).Count -gt 0

if ($hasCriticalCluster -or $hasAgentThresholdExceeded) {
    $overallStatus = "Critical"
}
elseif ($hasMediumCluster -or $highCount -ge $ClusterThreshold) {
    $overallStatus = "Warning"
}

#endregion

#region Build Result Object

$summaryResult = [PSCustomObject]@{
    OverallStatus = $overallStatus
    GeneratedAt   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    DaysBack      = $DaysBack
    Metrics       = [PSCustomObject]@{
        TotalReports   = $totalReports
        ResolvedCount  = $resolvedCount
        UnresolvedCount = $unresolvedCount
    }
    Distributions = [PSCustomObject]@{
        ByCategory = $categoryDistribution
        BySeverity = $severityDistribution
        BySource   = $sourceDistribution
    }
    TopAgents     = @($topAgents)
    Trends        = @($trendSorted)
    Patterns      = @($patterns)
}

#endregion

#region Output

switch ($OutputFormat) {
    'JSON' {
        $summaryResult | ConvertTo-Json -Depth 10
    }
    'Object' {
        return $summaryResult
    }
    'Table' {
        # Status color
        $statusColor = switch ($overallStatus) {
            'Healthy'  { 'Green' }
            'Warning'  { 'Yellow' }
            'Critical' { 'Red' }
        }

        Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor $statusColor
        Write-Host ("║  Overall Status: {0,-32}║" -f $overallStatus) -ForegroundColor $statusColor
        Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor $statusColor
        Write-Host ""

        # Key metrics
        Write-Host "── Key Metrics ($DaysBack days) ──────────────────" -ForegroundColor Cyan
        Write-Host ("  Total Reports:    {0}" -f $totalReports)
        Write-Host ("  Resolved:         {0}" -f $resolvedCount)
        Write-Host ("  Unresolved:       {0}" -f $unresolvedCount)
        Write-Host ""

        # Severity distribution
        if ($severityDistribution.Count -gt 0) {
            Write-Host "── Severity Distribution ─────────────────────────" -ForegroundColor Cyan
            foreach ($sev in @('Critical', 'High', 'Medium', 'Low')) {
                $count = if ($severityDistribution.ContainsKey($sev)) { $severityDistribution[$sev] } else { 0 }
                $sevColor = switch ($sev) {
                    'Critical' { 'Red' }
                    'High'     { 'Yellow' }
                    'Medium'   { 'DarkYellow' }
                    'Low'      { 'Gray' }
                }
                Write-Host ("  {0,-20} {1}" -f $sev, $count) -ForegroundColor $sevColor
            }
            Write-Host ""
        }

        # Category distribution
        if ($categoryDistribution.Count -gt 0) {
            Write-Host "── Category Distribution ─────────────────────────" -ForegroundColor Cyan
            foreach ($entry in ($categoryDistribution.GetEnumerator() | Sort-Object -Property Value -Descending)) {
                Write-Host ("  {0,-30} {1}" -f $entry.Key, $entry.Value)
            }
            Write-Host ""
        }

        # Source distribution
        if ($sourceDistribution.Count -gt 0) {
            Write-Host "── Source Distribution ───────────────────────────" -ForegroundColor Cyan
            foreach ($entry in ($sourceDistribution.GetEnumerator() | Sort-Object -Property Value -Descending)) {
                Write-Host ("  {0,-20} {1}" -f $entry.Key, $entry.Value)
            }
            Write-Host ""
        }

        # Top agents
        if ($topAgents.Count -gt 0) {
            Write-Host "── Top 5 Agents by Report Count ─────────────────" -ForegroundColor Cyan
            Write-Host ("  {0,-30} {1,-8} {2}" -f "Agent", "Count", "Rate")
            Write-Host ("  {0,-30} {1,-8} {2}" -f "─────", "─────", "────")
            foreach ($agent in $topAgents) {
                Write-Host ("  {0,-30} {1,-8} {2}" -f $agent.AgentId, $agent.ReportCount, $agent.HallucinationRate)
            }
            Write-Host ""
        }

        # Weekly trend
        if ($trendSorted.Count -gt 0) {
            Write-Host "── Weekly Trend ──────────────────────────────────" -ForegroundColor Cyan
            foreach ($week in $trendSorted) {
                $bar = '█' * [math]::Min($week.ReportCount, 40)
                Write-Host ("  {0}  {1,4}  {2}" -f $week.WeekStarting, $week.ReportCount, $bar)
            }
            Write-Host ""
        }

        # Patterns
        if ($patterns.Count -gt 0) {
            Write-Host "── Detected Patterns ─────────────────────────────" -ForegroundColor Yellow
            foreach ($pattern in $patterns) {
                Write-Host ("  ⚠ {0}: {1} reports (cluster threshold: {2})" -f $pattern.Category, $pattern.Count, $ClusterThreshold) -ForegroundColor Yellow
            }
            Write-Host ""
        }
        else {
            Write-Host "── Detected Patterns ─────────────────────────────" -ForegroundColor Cyan
            Write-Host "  No category clusters detected above threshold ($ClusterThreshold)." -ForegroundColor Green
            Write-Host ""
        }
    }
}

#endregion
