#Requires -Version 7.0
#Requires -Modules MSAL.PS

<#
.SYNOPSIS
    Syncs M365 Message Center posts to Dataverse for agent governance tracking.

.DESCRIPTION
    Pulls Microsoft 365 Message Center posts from the Graph API and upserts them
    into the fsi_messagecenterlog Dataverse table. New posts are created with an
    assessment status of NotAssessed; existing posts are updated with the latest
    body, tags, and timestamps.

    Supports Controls 2.3 (Change Management) and 2.10 (Platform Change Monitoring)
    from the FSI Agent Governance Framework.

    The script authenticates to Graph API via client credentials, pages through all
    matching announcements, and performs per-message upsert against Dataverse using
    the fsi_messagecenterid alternate key.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER ClientId
    Application (client) ID of the Entra app registration.
    Defaults to $env:AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Client secret as a SecureString. Required for client-credentials authentication.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER DaysBack
    Number of days to look back for modified messages. Default: 7.

.PARAMETER NotifySeverities
    Severity levels that should be flagged in the summary output.
    Default: @('high','critical').

.PARAMETER OutputFormat
    Output format for the sync summary. Table, JSON, or Object.
    Default: Table.

.EXAMPLE
    $secret = ConvertTo-SecureString "mySecret" -AsPlainText -Force
    .\Invoke-MessageCenterSync.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -ClientSecret $secret

    Syncs the last 7 days of Message Center posts using environment variables
    for TenantId and ClientId.

.EXAMPLE
    $secret = Read-Host -AsSecureString -Prompt "Client Secret"
    .\Invoke-MessageCenterSync.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -ClientSecret $secret `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -DaysBack 30 `
        -OutputFormat JSON

    Syncs 30 days of posts and outputs results as JSON.

.OUTPUTS
    PSCustomObject with sync summary: TotalSynced, NewRecords, UpdatedRecords,
    HighSeverityCount, CriticalCount, SyncTimestamp.

.NOTES
    Version: 1.0.0
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module
    - Entra app registration with ServiceMessage.Read.All (application permission)
    - Dataverse fsi_messagecenterlog table deployed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $true)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false)]
    [int]$DaysBack = 7,

    [Parameter(Mandatory = $false)]
    [string[]]$NotifySeverities = @('high', 'critical'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table'
)

$ErrorActionPreference = "Stop"

#region Validation

if (-not $TenantId) {
    throw "TenantId is required. Provide -TenantId or set `$env:AZURE_TENANT_ID."
}
if (-not $ClientId) {
    throw "ClientId is required. Provide -ClientId or set `$env:AZURE_CLIENT_ID."
}

#endregion

#region Banner

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Message Center Sync                             ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Message Center Monitor             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

#endregion

#region Authentication — Graph API

Write-Host "Authenticating to Microsoft Graph..." -ForegroundColor Cyan

Import-Module MSAL.PS -ErrorAction Stop

$graphToken = Get-MsalToken `
    -TenantId $TenantId `
    -ClientId $ClientId `
    -ClientSecret $ClientSecret `
    -Scopes @('https://graph.microsoft.com/.default')

$graphHeaders = @{
    Authorization  = "Bearer $($graphToken.AccessToken)"
    'Content-Type' = 'application/json'
}

Write-Host "Graph API authentication successful." -ForegroundColor Green

#endregion

#region Authentication — Dataverse

Write-Host "Authenticating to Dataverse..." -ForegroundColor Cyan

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"
$dvToken = Get-MsalToken `
    -TenantId $TenantId `
    -ClientId $ClientId `
    -ClientSecret $ClientSecret `
    -Scopes @($dataverseScope)

$dvHeaders = @{
    Authorization    = "Bearer $($dvToken.AccessToken)"
    'Content-Type'   = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
    Prefer           = 'return=representation'
}

$dvBaseUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

Write-Host "Dataverse authentication successful." -ForegroundColor Green
Write-Host ""

#endregion

#region Fetch Message Center Posts

$cutoffDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$selectFields = "id,title,category,severity,services,startDateTime,endDateTime,lastModifiedDateTime,isMajorChange,actionRequiredByDateTime,body,tags,hasAttachments"
$graphUrl = "https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages?`$select=$selectFields&`$filter=lastModifiedDateTime ge $cutoffDate"

Write-Host "Fetching Message Center posts (last $DaysBack days)..." -ForegroundColor Cyan

# Throttling-aware REST helper. Honors Retry-After (seconds or HTTP-date) for
# 429 / 503 responses; falls back to exponential backoff if header is missing.
function Invoke-MCMRest {
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [hashtable]$Headers,
        [Parameter(Mandatory)] [string]$Method,
        [string]$Body,
        [int]$MaxRetries = 5
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($PSBoundParameters.ContainsKey('Body') -and $Body) {
                return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $Body
            } else {
                return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
            }
        }
        catch {
            $status = $null
            try { $status = [int]$_.Exception.Response.StatusCode } catch {}
            if (($status -eq 429 -or $status -eq 503) -and $attempt -le $MaxRetries) {
                $retryAfter = 0
                try { $retryAfter = [int]$_.Exception.Response.Headers['Retry-After'] } catch {}
                if ($retryAfter -le 0) { $retryAfter = [Math]::Min(60, [Math]::Pow(2, $attempt)) }
                Write-Warning "  Throttled ($status). Sleeping $retryAfter s (attempt $attempt/$MaxRetries)..."
                Start-Sleep -Seconds $retryAfter
                continue
            }
            throw
        }
    }
}

$allMessages = [System.Collections.Generic.List[object]]::new()

$pageUrl = $graphUrl
while ($pageUrl) {
    $response = Invoke-MCMRest -Uri $pageUrl -Headers $graphHeaders -Method Get
    if ($response.value) {
        $allMessages.AddRange($response.value)
    }
    $pageUrl = $response.'@odata.nextLink'
    if ($pageUrl) {
        Write-Verbose "Fetching next page ($($allMessages.Count) messages so far)..."
    }
}

Write-Host "Retrieved $($allMessages.Count) messages from Message Center." -ForegroundColor Green
Write-Host ""

#endregion

#region Mapping Helpers

$categoryMap = @{
    'planForChange'     = 100000000  # Feature
    'stayInformed'      = 100000001  # Admin
    'preventOrFixIssue' = 100000002  # Security
}

$severityMap = @{
    'high'     = 100000000  # High
    'normal'   = 100000001  # Normal
    'critical' = 100000002  # Critical
}

# Assessment status: NotAssessed = 100000000
$assessmentNotAssessed = 100000000

#endregion

#region Upsert Messages to Dataverse

$newCount = 0
$updatedCount = 0
$failedCount = 0
$failedIds = [System.Collections.Generic.List[string]]::new()
$highCriticalCount = 0

# Dataverse Memo column upper bound for fsi_body — keep one byte of headroom
# for the truncation marker so very long Message Center HTML bodies can still
# be persisted without a 0x80040217 PayloadTooLarge failure.
$bodyMaxLength = 99990

foreach ($msg in $allMessages) {
    $messageId = $msg.id

    # Map category and severity to Dataverse choice values
    $categoryValue = $categoryMap[$msg.category]
    if ($null -eq $categoryValue) { $categoryValue = 100000001 }  # Default: Admin

    $severityValue = $severityMap[$msg.severity]
    if ($null -eq $severityValue) { $severityValue = 100000001 }  # Default: Normal

    # Track high/critical messages
    if ($msg.severity -in $NotifySeverities) {
        $highCriticalCount++
    }

    # Flatten services array and tags array to comma-separated strings
    $servicesStr = if ($msg.services) { ($msg.services -join ', ') } else { $null }
    $tagsStr = if ($msg.tags) { ($msg.tags -join ', ') } else { $null }
    $bodyContent = if ($msg.body -and $msg.body.content) { $msg.body.content } else { $null }
    if ($bodyContent -and $bodyContent.Length -gt $bodyMaxLength) {
        $bodyContent = $bodyContent.Substring(0, $bodyMaxLength) + "`n[truncated — original length $($bodyContent.Length) chars]"
    }

    # Check if record exists by fsi_messagecenterid
    $filterUrl = "$dvBaseUrl/fsi_messagecenterlogs?`$filter=fsi_messagecenterid eq '$messageId'&`$select=fsi_messagecenterlogid&`$top=1"
    try {
        $existing = Invoke-MCMRest -Uri $filterUrl -Headers $dvHeaders -Method Get
    }
    catch {
        Write-Warning "Failed to query Dataverse for message $messageId : $($_.Exception.Message)"
        $failedCount++
        [void]$failedIds.Add($messageId)
        continue
    }

    # Build the record payload
    $record = @{
        fsi_messagecenterid        = $messageId
        fsi_title                  = $msg.title
        fsi_category               = $categoryValue
        fsi_severity               = $severityValue
        fsi_services               = $servicesStr
        fsi_startdatetime          = $msg.startDateTime
        fsi_lastmodifieddatetime   = $msg.lastModifiedDateTime
        fsi_ismajorchange          = [bool]$msg.isMajorChange
        fsi_body                   = $bodyContent
        fsi_tags                   = $tagsStr
        fsi_hasattachments         = [bool]$msg.hasAttachments
    }

    # Optional date fields (null-safe)
    if ($msg.endDateTime) {
        $record.fsi_enddatetime = $msg.endDateTime
    }
    if ($msg.actionRequiredByDateTime) {
        $record.fsi_actionrequiredbydatetime = $msg.actionRequiredByDateTime
    }

    $jsonBody = $record | ConvertTo-Json -Depth 5

    if ($existing.value -and $existing.value.Count -gt 0) {
        # Update existing record
        $recordId = $existing.value[0].fsi_messagecenterlogid
        $patchUrl = "$dvBaseUrl/fsi_messagecenterlogs($recordId)"
        try {
            Invoke-MCMRest -Uri $patchUrl -Headers $dvHeaders -Method Patch -Body $jsonBody | Out-Null
            $updatedCount++
            Write-Verbose "Updated: $messageId — $($msg.title)"
        }
        catch {
            Write-Warning "Failed to update message $messageId : $($_.Exception.Message)"
            $failedCount++
            [void]$failedIds.Add($messageId)
        }
    }
    else {
        # Create new record with NotAssessed status
        $record.fsi_assessmentstatus = $assessmentNotAssessed
        $jsonBody = $record | ConvertTo-Json -Depth 5

        $postUrl = "$dvBaseUrl/fsi_messagecenterlogs"
        try {
            Invoke-MCMRest -Uri $postUrl -Headers $dvHeaders -Method Post -Body $jsonBody | Out-Null
            $newCount++
            Write-Verbose "Created: $messageId — $($msg.title)"
        }
        catch {
            Write-Warning "Failed to create message $messageId : $($_.Exception.Message)"
            $failedCount++
            [void]$failedIds.Add($messageId)
        }
    }
}

#endregion

#region Output Summary

$syncTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$summary = [PSCustomObject]@{
    TotalSynced       = $allMessages.Count
    NewRecords        = $newCount
    UpdatedRecords    = $updatedCount
    FailedRecords     = $failedCount
    FailedMessageIds  = $failedIds.ToArray()
    HighSeverityCount = ($allMessages | Where-Object { $_.severity -eq 'high' }).Count
    CriticalCount     = ($allMessages | Where-Object { $_.severity -eq 'critical' }).Count
    SyncTimestamp     = $syncTimestamp
}

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       Sync Summary                               ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host ("║ Total Synced:     {0,-31}║" -f $summary.TotalSynced) -ForegroundColor Cyan
Write-Host ("║ New Records:      {0,-31}║" -f $summary.NewRecords) -ForegroundColor Cyan
Write-Host ("║ Updated Records:  {0,-31}║" -f $summary.UpdatedRecords) -ForegroundColor Cyan
Write-Host ("║ Failed Records:   {0,-31}║" -f $summary.FailedRecords) -ForegroundColor $(if ($failedCount -gt 0) { 'Red' } else { 'Cyan' })
Write-Host ("║ High Severity:    {0,-31}║" -f $summary.HighSeverityCount) -ForegroundColor Cyan
Write-Host ("║ Critical:         {0,-31}║" -f $summary.CriticalCount) -ForegroundColor Cyan
Write-Host ("║ Synced At:        {0,-31}║" -f $summary.SyncTimestamp) -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($failedCount -gt 0) {
    Write-Warning "$failedCount message(s) failed to persist to Dataverse: $($failedIds -join ', ')"
}

if ($highCriticalCount -gt 0) {
    Write-Warning "$highCriticalCount message(s) matched notify severity filter ($($NotifySeverities -join ', '))."
}

switch ($OutputFormat) {
    'Table' {
        $summary | Format-Table -AutoSize
    }
    'JSON' {
        $summary | ConvertTo-Json -Depth 5
    }
    'Object' {
        # Object output is returned to the pipeline; callers can still
        # inspect $LASTEXITCODE for partial-failure detection.
        if ($failedCount -gt 0) { $global:LASTEXITCODE = 1 }
        return $summary
    }
}

# Surface partial-failure as a non-zero exit code so scheduled runs
# (Azure Automation, Logic Apps, GitHub Actions) can alert on it.
if ($failedCount -gt 0) { exit 1 }

#endregion
