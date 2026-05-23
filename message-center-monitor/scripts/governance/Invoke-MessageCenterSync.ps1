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

    Supports Control 2.3 (Change Management and Release Planning) from the FSI Agent
    Governance Framework.

    The script authenticates to Microsoft Graph using managed-identity-first modes,
    pages through matching announcements, and performs per-message upsert against
    Dataverse using the fsi_messagecenterid alternate key.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER ClientId
    Application (client) ID of the Entra app registration.
    Defaults to $env:AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Client secret as a SecureString. Required only when -AuthMode ClientSecret.
    legacy: dev-only — replace with managed identity in production.

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

.PARAMETER TeamsWebhookUrl
    Optional Microsoft Teams Workflows incoming webhook URL. When supplied
    (or set via $env:MCM_TEAMS_WEBHOOK_URL), high/critical messages (or
    whatever -NotifySeverities specifies) are posted to the configured Teams
    channel as adaptive cards. Empty / unset disables Teams notification.

    Phase 1 notification path. MUTUALLY EXCLUSIVE with the Phase 3 Power
    Automate flow; run Test-McmPrerequisites.ps1 first to confirm only one
    path is active.

.PARAMETER ModelDrivenAppId
    Optional model-driven app id (GUID) used to construct the "Assess Record"
    deep-link in the Teams adaptive card. When omitted, the deep-link button
    will be malformed but the alert still posts.

.PARAMETER DryRun
    Skip all Dataverse mutations and Teams notifications. Useful for
    validating auth + Graph reachability without side effects.

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
    Version: 2.5.1
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
    [string]$TeamsWebhookUrl = $env:MCM_TEAMS_WEBHOOK_URL,

    [Parameter(Mandatory = $false)]
    [string]$ModelDrivenAppId = $env:MCM_MODEL_DRIVEN_APP_ID,

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
    # StrictMode (Version Latest) throws on a missing property access via dot
    # syntax. Graph returns @odata.nextLink only when there's another page;
    # use PSObject.Properties to probe-then-read.
    $pageUrl = if ($response.PSObject.Properties['@odata.nextLink']) { $response.'@odata.nextLink' } else { $null }
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
$notifiedCount = 0
$notifySkippedCount = 0
$notifyFailedCount = 0
$notifyWriteBackFailedCount = 0

# Resolve the shared adaptive card template. The same template is rendered
# here (Phase 1) and by the Power Automate flow (Phase 3); the two paths
# are mutually exclusive at runtime - see Test-McmPrerequisites.ps1.
$cardTemplatePath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'templates/teams-notification-card.json'

# Parse the Dataverse hostname's first label for use in the card's
# "Assess Record" deep-link (e.g. https://contoso.crm.dynamics.com -> 'contoso').
# Sovereign-cloud regions with a non-public-cloud URL pattern will produce
# a broken deep-link; the alert payload itself still delivers correctly.
$environmentLabel = ''
try {
    $hostLabel = ([uri]$DataverseUrl).Host
    if ($hostLabel) { $environmentLabel = ($hostLabel -split '\.')[0] }
} catch {
    Write-Verbose "Could not parse DataverseUrl hostname for environment label: $($_.Exception.Message)"
}

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

    # Build the upsert payload. Admin-owned columns (fsi_assessmentstatus,
    # fsi_assessment, fsi_assessedby, fsi_assesseddate, fsi_actionstaken,
    # fsi_impactsagents, fsi_notifiedon) are deliberately EXCLUDED so the
    # update path cannot clobber them. fsi_assessmentstatus is added later in
    # the create-only payload.
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

    if ($DryRun) {
        Write-Verbose "DryRun: would upsert $messageId — $($msg.title)"
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($messageId, 'Upsert MessageCenterLog')) {
        continue
    }

    # Conditional create vs preserve-on-update branching is encapsulated in
    # Invoke-McmDvUpsertMessage (in _Common.ps1) so the C1 logic is unit-testable.
    # The function returns Action=Created or Action=Updated; throws on terminal
    # failure (alt-key 404, create errors other than 412, update errors).
    try {
        $result = Invoke-McmDvUpsertMessage -DataverseBaseUrl $dvBaseUrl `
            -MessageId $messageId -Record $record `
            -DataverseHeaders $dvHeaders `
            -AssessmentNotAssessedValue $assessmentNotAssessed
        if ($result.Action -eq 'Created') {
            $newCount++
            Write-Verbose "Created: $messageId — $($msg.title)"
        }
        else {
            $updatedCount++
            Write-Verbose "Updated: $messageId — $($msg.title) (admin assessment preserved)"
        }
    }
    catch {
        Write-Warning $_.Exception.Message
        $failedCount++
        [void]$failedIds.Add($messageId)
        continue
    }

    # ---------- Phase 1 Teams notification ----------------------------------
    # Posts a Teams adaptive card when (a) a webhook URL is configured,
    # (b) the message severity matches -NotifySeverities, and (c) the row
    # has not already been notified (idempotency via fsi_notifiedon).
    #
    # On successful POST, writes fsi_notifiedon via a DIRECT PATCH using
    # Invoke-McmRest with a single-field body. This bypasses
    # Invoke-McmDvUpsertMessage on purpose: that helper's contract forbids
    # admin-owned columns (the C1 invariant) and is enforced by static checks
    # in tests/Sync.Tests.ps1.
    #
    # Phase 1 ↔ Phase 3 are MUTUALLY EXCLUSIVE; Test-McmPrerequisites.ps1
    # FAILs the preflight if both webhook env-var AND flow env-var are
    # deployed at the same time. fsi_notifiedon provides per-row idempotency
    # within ONE path only, not cross-path dedup.
    if ($TeamsWebhookUrl -and ($msg.severity -in $NotifySeverities)) {
        $alreadyNotified = $false
        $existingNotifiedOn = $null
        if ($result.ResponseBody -and ($result.ResponseBody.PSObject.Properties.Name -contains 'fsi_notifiedon')) {
            $existingNotifiedOn = $result.ResponseBody.fsi_notifiedon
        }
        if ($existingNotifiedOn -and ([string]$existingNotifiedOn).Trim()) {
            $alreadyNotified = $true
        }

        if ($alreadyNotified) {
            Write-Verbose "Notify skipped (already notified): $messageId"
            $notifySkippedCount++
        }
        elseif (-not $result.EntityId) {
            Write-Verbose "Notify skipped (no EntityId from upsert response - Prefer header may be missing): $messageId"
            $notifySkippedCount++
        }
        else {
            $cardTokens = @{
                severity                 = if ($msg.severity)                 { [string]$msg.severity }                 else { 'normal' }
                title                    = if ($msg.title)                    { [string]$msg.title }                    else { '(no title)' }
                category                 = if ($msg.category)                 { [string]$msg.category }                 else { 'stayInformed' }
                services                 = if ($servicesStr)                  { $servicesStr }                          else { '' }
                startDateTime            = if ($msg.startDateTime)            { [string]$msg.startDateTime }            else { '' }
                actionRequiredByDateTime = if ($msg.actionRequiredByDateTime) { [string]$msg.actionRequiredByDateTime } else { 'None' }
                id                       = $messageId
                environment              = $environmentLabel
                appId                    = if ($ModelDrivenAppId)             { $ModelDrivenAppId }                    else { '' }
                publisherPrefix          = 'fsi'
                recordId                 = $result.EntityId
            }

            try {
                $notifyResult = Send-McmTeamsWebhook -WebhookUrl $TeamsWebhookUrl `
                    -CardTokens $cardTokens `
                    -AdaptiveCardTemplatePath $cardTemplatePath
            } catch {
                $notifyResult = [pscustomobject]@{ Success = $false; Error = $_.Exception.Message }
            }

            if ($notifyResult.Success) {
                # Direct PATCH for the single admin-owned column fsi_notifiedon.
                # Does NOT route through Invoke-McmDvUpsertMessage (C1 contract).
                $escapedId = Format-McmODataLiteral $messageId
                $patchUrl = "$dvBaseUrl/fsi_messagecenterlogs(fsi_messagecenterid='$escapedId')"
                $patchBody = @{ fsi_notifiedon = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress
                try {
                    $null = Invoke-McmRest -Uri $patchUrl -Headers $dvHeaders -Method Patch -Body $patchBody
                    $notifiedCount++
                    Write-Verbose "Notified + write-back complete: $messageId"
                } catch {
                    Write-Warning "Teams notification POSTED for ${messageId} but fsi_notifiedon write-back FAILED: $($_.Exception.Message)"
                    $notifyWriteBackFailedCount++
                }
            } else {
                Write-Warning "Teams notification failed for ${messageId}: $($notifyResult.Error)"
                $notifyFailedCount++
            }
        }
    }
}

#endregion

#region Output Summary

$syncTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$summary = [PSCustomObject]@{
    TotalSynced                = $allMessages.Count
    NewRecords                 = $newCount
    UpdatedRecords             = $updatedCount
    FailedRecords              = $failedCount
    FailedMessageIds           = $failedIds.ToArray()
    HighSeverityCount          = ($allMessages | Where-Object { $_.severity -eq 'high' }).Count
    CriticalCount              = ($allMessages | Where-Object { $_.severity -eq 'critical' }).Count
    NotifiedCount              = $notifiedCount
    NotifySkippedCount         = $notifySkippedCount
    NotifyFailedCount          = $notifyFailedCount
    NotifyWriteBackFailedCount = $notifyWriteBackFailedCount
    SyncTimestamp              = $syncTimestamp
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
if ($TeamsWebhookUrl) {
    Write-Host ("║ Notified (Teams): {0,-31}║" -f $summary.NotifiedCount) -ForegroundColor Cyan
    if ($summary.NotifySkippedCount -gt 0) {
        Write-Host ("║ Notify Skipped:   {0,-31}║" -f $summary.NotifySkippedCount) -ForegroundColor Cyan
    }
    if ($summary.NotifyFailedCount -gt 0 -or $summary.NotifyWriteBackFailedCount -gt 0) {
        $notifyFailedDisplay = "$($summary.NotifyFailedCount) (writeback: $($summary.NotifyWriteBackFailedCount))"
        Write-Host ("║ Notify Failed:    {0,-31}║" -f $notifyFailedDisplay) -ForegroundColor Yellow
    }
}
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
        # Emit the summary to the pipeline so -OutputFormat Object callers
        # still receive the structured result. Do NOT 'return' here: the
        # unified exit-code logic below must run for all formats so
        # scheduled callers (pwsh -File ...) see process exit = 1 on
        # partial failure. Setting $global:LASTEXITCODE = 1 is NOT
        # sufficient - $LASTEXITCODE only reflects the last native-command
        # exit and does NOT set the host process exit code; that requires
        # an explicit 'exit N' statement.
        $summary
    }
}

# Surface partial-failure as a non-zero exit code so scheduled runs
# (Azure Automation, Logic Apps, GitHub Actions) can alert on it.
# Notification failures count as terminal failures: a silent webhook
# regression is the same severity as a silent Dataverse regression for
# the customer's POC, and on a write-back failure the NEXT run will
# re-post the same Teams alert because fsi_notifiedon was never written.
$terminalFailures = $failedCount + $notifyFailedCount + $notifyWriteBackFailedCount
if ($terminalFailures -gt 0) { exit 1 }

#endregion
