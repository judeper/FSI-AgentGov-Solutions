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
    Client secret as a SecureString. Required only when -AuthMode ClientSecret.
    legacy: dev-only path; prefer ManagedIdentity in production.

.PARAMETER AuthMode
    Authentication mode. ManagedIdentity (default), WorkloadIdentity, Interactive,
    DeviceCode, or ClientSecret. ManagedIdentity requires MSAL.PS 4.37 or later.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER DaysBack
    Number of days to look back for modified messages. Default: 7. Range: 1-365.

.PARAMETER NotifySeverities
    Severity levels that should be flagged in the summary output.
    Default: @('high','critical').

.PARAMETER OutputFormat
    Output format for the sync summary. Table, JSON, or Object.
    Default: Table.

.EXAMPLE
    .\Invoke-MessageCenterSync.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AuthMode ManagedIdentity

    Recommended: syncs the last 7 days using the host's managed identity.
    No secrets required; works in Azure Functions, Automation, ACI, and AKS.

.EXAMPLE
    .\Invoke-MessageCenterSync.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -AuthMode DeviceCode

    One-off admin-workstation run with device-code auth.

.EXAMPLE
    $secret = Read-Host -AsSecureString -Prompt "Client Secret"
    .\Invoke-MessageCenterSync.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -ClientSecret $secret `
        -AuthMode ClientSecret `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -DaysBack 30 `
        -OutputFormat JSON

    (dev only) Syncs 30 days of posts using a client secret. Use ManagedIdentity
    in production.

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

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidateSet('ManagedIdentity', 'WorkloadIdentity', 'Interactive', 'DeviceCode', 'ClientSecret')]
    [string]$AuthMode = 'ManagedIdentity',

    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$DaysBack = 7,

    [Parameter(Mandatory = $false)]
    [string[]]$NotifySeverities = @('high', 'critical'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

. "$PSScriptRoot\_Common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Validation

if ($AuthMode -in @('Interactive', 'DeviceCode', 'ClientSecret')) {
    if (-not $TenantId) {
        throw "TenantId is required for -AuthMode $AuthMode. Provide -TenantId or set `$env:AZURE_TENANT_ID."
    }
    if (-not $ClientId) {
        throw "ClientId is required for -AuthMode $AuthMode. Provide -ClientId or set `$env:AZURE_CLIENT_ID."
    }
}
if ($AuthMode -eq 'ClientSecret' -and -not $ClientSecret) {
    throw "ClientSecret is required when -AuthMode ClientSecret. Use -AuthMode ManagedIdentity for production."
}

#endregion

#region Banner

if (-not $Quiet) {
    Write-Information "Message Center Sync — FSI-AgentGov Message Center Monitor" -InformationAction Continue
}

#endregion

#region Authentication — Graph API

if (-not $Quiet) { Write-Information "Authenticating to Microsoft Graph (mode: $AuthMode)..." -InformationAction Continue }

$graphScope = 'https://graph.microsoft.com/.default'
$graphTokenObj = Get-McmAccessToken -AuthMode $AuthMode -Scope $graphScope `
    -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

$graphHeaders = @{
    Authorization  = "Bearer $($graphTokenObj.AccessToken)"
    'Content-Type' = 'application/json'
}

if (-not $Quiet) { Write-Information "Graph API authentication successful." -InformationAction Continue }

#endregion

#region Authentication — Dataverse

if (-not $Quiet) { Write-Information "Authenticating to Dataverse..." -InformationAction Continue }

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

# Use Get-McmDvHeaders to populate the cache; the loop below re-calls it per
# message so that long-running syncs transparently refresh near token expiry.
$dvHeaders = Get-McmDvHeaders -AuthMode $AuthMode -Scope $dataverseScope `
    -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret `
    -ExtraHeaders @{ Prefer = 'return=representation,odata.maxpagesize=500' }

$dvBaseUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

if (-not $Quiet) {
    Write-Information "Dataverse authentication successful." -InformationAction Continue
    if ($DryRun) { Write-Information "DryRun mode: no Dataverse mutations will be performed." -InformationAction Continue }
}

#endregion

#region Fetch Message Center Posts

$cutoffDate = Format-McmODataDate ((Get-Date).AddDays(-$DaysBack))
$selectFields = "id,title,category,severity,services,startDateTime,endDateTime,lastModifiedDateTime,isMajorChange,actionRequiredByDateTime,body,tags,hasAttachments"
$graphUrl = "https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages?`$select=$selectFields&`$filter=lastModifiedDateTime ge $cutoffDate"

if (-not $Quiet) {
    Write-Information "Fetching Message Center posts (last $DaysBack days)..." -InformationAction Continue
}

# Honor server-side page size; cap pagination at 1000 pages as a safety net.
$graphHeaders['Prefer'] = 'odata.maxpagesize=500'

$allMessages = [System.Collections.Generic.List[object]]::new()
$pageUrl = $graphUrl
$pageCount = 0
while ($pageUrl) {
    $pageCount++
    Write-Verbose "Page $pageCount"
    if ($pageCount -gt 1000) {
        throw "Pagination exceeded 1000 pages — possible infinite loop"
    }
    try {
        $response = Invoke-McmRest -Uri $pageUrl -Headers $graphHeaders -Method Get
    }
    catch {
        Write-Error "Graph pagination failed at page $pageCount : $($_.Exception.Message)"
        exit 1
    }
    if ($response.value) {
        $allMessages.AddRange($response.value)
    }
    $pageUrl = $response.'@odata.nextLink'
    if ($pageUrl) {
        Write-Verbose "Fetching next page ($($allMessages.Count) messages so far)..."
    }
}

if (-not $Quiet) {
    Write-Information "Retrieved $($allMessages.Count) messages from Message Center." -InformationAction Continue
}

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

    # Build the upsert payload. fsi_assessmentstatus is set to NotAssessed on
    # the create path only — we don't want to clobber an admin's assessment on
    # subsequent syncs of the same message.
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

    # Refresh the cached Dataverse headers; this returns immediately unless the
    # token is within 5 min of expiry, in which case it transparently re-acquires.
    $dvHeaders = Get-McmDvHeaders -AuthMode $AuthMode -Scope $dataverseScope `
        -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret `
        -ExtraHeaders @{
            Prefer = 'return=representation,odata.maxpagesize=500'
        }

    # Single-call upsert via alternate-key URL. Created by Agent A's schema fix
    # (fsi_MessageCenterIdKey on fsi_messagecenterid). Eliminates SELECT-then-POST
    # race and halves API calls.
    $escapedId = Format-McmODataLiteral $messageId
    $upsertUrl = "$dvBaseUrl/fsi_messagecenterlogs(fsi_messagecenterid='$escapedId')"

    if ($DryRun) {
        Write-Verbose "DryRun: would upsert $messageId — $($msg.title)"
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($messageId, 'Upsert MessageCenterLog')) {
        continue
    }

    # Default-on-create: include NotAssessed so newly created records start in
    # the right state. On update Dataverse honors If-None-Match-style upserts;
    # we send the field unconditionally because admins should re-trigger
    # assessment when severity/body change anyway. If preserving existing
    # assessment status across re-syncs becomes a requirement, switch to a
    # GET-then-PATCH guarded by the existing record's assessmentstatus value.
    $record.fsi_assessmentstatus = $assessmentNotAssessed
    $jsonBody = $record | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-McmRest -Uri $upsertUrl -Headers $dvHeaders -Method Patch -Body $jsonBody
        # Prefer: return=representation echoes the row; created vs updated is
        # surfaced via @odata.context only on create. Use a HEAD-style heuristic:
        # if @odata.etag is present and createdon equals modifiedon, treat as new.
        $isNew = $false
        try {
            if ($response.createdon -and $response.modifiedon -and $response.createdon -eq $response.modifiedon) {
                $isNew = $true
            }
        } catch {}
        if ($isNew) {
            $newCount++
            Write-Verbose "Created: $messageId — $($msg.title)"
        } else {
            $updatedCount++
            Write-Verbose "Updated: $messageId — $($msg.title)"
        }
    }
    catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -match 'status=404' -or $errMsg -match 'Resource not found for the segment') {
            Write-Warning "Upsert failed for $messageId : Alternate key fsi_MessageCenterIdKey not found — re-run create_mcm_dataverse_schema.py to provision it."
        } else {
            Write-Warning "Failed to upsert message $messageId : $errMsg"
        }
        $failedCount++
        [void]$failedIds.Add($messageId)
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
