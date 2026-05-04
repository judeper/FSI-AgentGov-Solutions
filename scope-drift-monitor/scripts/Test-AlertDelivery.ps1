#Requires -Version 7.0

<#
.SYNOPSIS
    Tests alert delivery channels for Scope Drift Monitor.

.DESCRIPTION
    Sends test notifications via Teams webhook and/or email to verify
    alert delivery configuration before production deployment.

.PARAMETER Channel
    Which channels to test: Teams, Email, or Both.

.PARAMETER TeamsWebhook
    Teams webhook URL. Can also be set via SDM_TEAMS_WEBHOOK environment variable.

.PARAMETER EmailRecipient
    Email address for test notifications. Can also be set via SDM_NOTIFICATION_EMAIL.

.PARAMETER FromEmail
    Sender email address (must have Mail.Send permission in Microsoft Graph).
    Can also be set via SDM_FROM_EMAIL environment variable.

.EXAMPLE
    .\Test-AlertDelivery.ps1 -Channel Teams -TeamsWebhook "https://..."
    Tests Teams webhook delivery.

.EXAMPLE
    .\Test-AlertDelivery.ps1 -Channel Both -TeamsWebhook "https://..." -EmailRecipient "security@contoso.com"
    Tests both Teams and email delivery.

.EXAMPLE
    .\Test-AlertDelivery.ps1 -Channel Email -EmailRecipient "security@contoso.com" -FromEmail "alerts@contoso.com"
    Tests email delivery only via Microsoft Graph.

.NOTES
    Teams incoming webhooks retired March 31, 2026.
    Use Power Automate workflows for production deployments.
    Email delivery uses Send-MgUserMail (Microsoft Graph). Requires
    Microsoft.Graph.Users.Actions module and Mail.Send permission.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Teams", "Email", "Both")]
    [string]$Channel,

    [Parameter(Mandatory = $false)]
    [string]$TeamsWebhook = $env:SDM_TEAMS_WEBHOOK,

    [Parameter(Mandatory = $false)]
    [string]$EmailRecipient = $env:SDM_NOTIFICATION_EMAIL,

    [Parameter(Mandatory = $false)]
    [string]$FromEmail = $env:SDM_FROM_EMAIL
)

$ErrorActionPreference = "Stop"

#region Adaptive Card Template

function Get-TestAdaptiveCard {
    <#
    .SYNOPSIS
        Creates an Adaptive Card JSON for test notification.
    #>

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $card = @{
        "type"    = "message"
        "attachments" = @(
            @{
                "contentType" = "application/vnd.microsoft.card.adaptive"
                "content"     = @{
                    "`$schema" = "http://adaptivecards.io/schemas/adaptive-card.json"
                    "type"     = "AdaptiveCard"
                    "version"  = "1.5"
                    "body"     = @(
                        @{
                            "type"    = "Container"
                            "style"   = "attention"
                            "items"   = @(
                                @{
                                    "type"   = "TextBlock"
                                    "text"   = "Scope Drift Monitor - Test Alert"
                                    "weight" = "Bolder"
                                    "size"   = "Large"
                                    "color"  = "Attention"
                                }
                            )
                        }
                        @{
                            "type" = "TextBlock"
                            "text" = "This is a test notification to verify alert delivery configuration."
                            "wrap" = $true
                        }
                        @{
                            "type"  = "FactSet"
                            "facts" = @(
                                @{ "title" = "Agent"; "value" = "Test Agent (Demo)" }
                                @{ "title" = "Violation"; "value" = "Unauthorized SharePoint Site" }
                                @{ "title" = "Resource"; "value" = "https://contoso.sharepoint.com/sites/HR-Policies" }
                                @{ "title" = "Severity"; "value" = "Medium" }
                                @{ "title" = "Detected"; "value" = $timestamp }
                            )
                        }
                        @{
                            "type"  = "TextBlock"
                            "text"  = "This is a TEST message. No action required."
                            "wrap"  = $true
                            "color" = "Good"
                        }
                    )
                    "actions" = @(
                        @{
                            "type"  = "Action.OpenUrl"
                            "title" = "View Documentation"
                            "url"   = "https://github.com/judeper/FSI-AgentGov-Solutions/tree/main/scope-drift-monitor"
                        }
                    )
                }
            }
        )
    }

    return $card
}

#endregion

#region Helper Functions

function Send-TeamsNotification {
    <#
    .SYNOPSIS
        Sends an Adaptive Card to Teams via webhook.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebhookUrl
    )

    # Validate webhook URL is a Microsoft Teams endpoint
    $uri = [System.Uri]::new($WebhookUrl)
    $allowedHosts = @('outlook.office.com', 'outlook.office365.com', '*.webhook.office.com')
    $hostAllowed = $false
    foreach ($pattern in $allowedHosts) {
        if ($pattern.StartsWith('*')) {
            if ($uri.Host.EndsWith($pattern.Substring(1))) { $hostAllowed = $true; break }
        } elseif ($uri.Host -eq $pattern) {
            $hostAllowed = $true; break
        }
    }
    if (-not $hostAllowed) {
        return @{
            Success = $false
            Message = "Webhook URL host '$($uri.Host)' is not a recognized Microsoft Teams endpoint"
        }
    }

    $card = Get-TestAdaptiveCard
    $body = $card | ConvertTo-Json -Depth 20

    try {
        $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType "application/json"

        # Successful post returns 1 (or sometimes empty response)
        if ($response -eq 1 -or $null -eq $response) {
            return @{
                Success = $true
                Message = "Teams notification sent successfully"
            }
        }
        else {
            return @{
                Success = $false
                Message = "Unexpected response from Teams webhook: $response"
            }
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to send Teams notification: $($_.Exception.Message)"
        }
    }
}

function Send-EmailNotification {
    <#
    .SYNOPSIS
        Sends a test email notification via Microsoft Graph.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$To,

        [Parameter(Mandatory = $true)]
        [string]$From
    )

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $subject = "[TEST] Scope Drift Monitor Alert Test"

    $htmlBody = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Segoe UI, Arial, sans-serif; color: #333; }
        .header { background-color: #D13438; color: white; padding: 15px; }
        .content { padding: 20px; }
        .fact-table { border-collapse: collapse; margin: 15px 0; }
        .fact-table td { padding: 8px 12px; border-bottom: 1px solid #ddd; }
        .fact-table td:first-child { font-weight: bold; color: #666; }
        .test-notice { background-color: #DFF6DD; padding: 10px; border-left: 4px solid #107C10; margin: 15px 0; }
        .footer { color: #666; font-size: 12px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="header">
        <h2>Scope Drift Monitor - Test Alert</h2>
    </div>
    <div class="content">
        <p>This is a test notification to verify alert delivery configuration.</p>

        <table class="fact-table">
            <tr><td>Agent:</td><td>Test Agent (Demo)</td></tr>
            <tr><td>Violation:</td><td>Unauthorized SharePoint Site</td></tr>
            <tr><td>Resource:</td><td>https://contoso.sharepoint.com/sites/HR-Policies</td></tr>
            <tr><td>Severity:</td><td>Medium</td></tr>
            <tr><td>Detected:</td><td>$timestamp</td></tr>
        </table>

        <div class="test-notice">
            <strong>This is a TEST message.</strong> No action required.
        </div>

        <p>
            <a href="https://github.com/judeper/FSI-AgentGov-Solutions/tree/main/scope-drift-monitor">View Documentation</a>
        </p>

        <div class="footer">
            <p>FSI Agent Governance Framework - Scope Drift Monitor</p>
            <p>Sent: $timestamp</p>
        </div>
    </div>
</body>
</html>
"@

    $params = @{
        Message = @{
            Subject       = $subject
            Body          = @{ ContentType = "HTML"; Content = $htmlBody }
            ToRecipients  = @(@{ EmailAddress = @{ Address = $To } })
        }
    }

    try {
        # Ensure Microsoft Graph context exists; Send-MgUserMail otherwise fails
        # with an opaque "AuthenticationRequired" error.
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if ($null -eq $ctx) {
            Write-Host "  Connecting to Microsoft Graph (Mail.Send scope required)..." -ForegroundColor Gray
            Connect-MgGraph -Scopes "Mail.Send" -NoWelcome -ErrorAction Stop | Out-Null
        }
        elseif ($ctx.Scopes -notcontains "Mail.Send") {
            Write-Warning "Current Graph context lacks Mail.Send scope (has: $($ctx.Scopes -join ', ')). Re-connecting..."
            Connect-MgGraph -Scopes "Mail.Send" -NoWelcome -ErrorAction Stop | Out-Null
        }

        Send-MgUserMail -UserId $From -BodyParameter $params
        return @{
            Success = $true
            Message = "Email notification sent successfully to $To"
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to send email notification: $($_.Exception.Message)"
        }
    }
}

#endregion

#region Main Script

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Alert Delivery Test Utility" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Retirement warning for Teams webhooks
Write-Warning "Teams incoming webhooks retired March 31, 2026. Use Power Automate for production alerts."
Write-Host ""

Write-Host "Channel: $Channel"
Write-Host ""

$results = @{
    Teams = $null
    Email = $null
}

$hasFailure = $false

# Test Teams if requested
if ($Channel -eq "Teams" -or $Channel -eq "Both") {
    Write-Host "Testing Teams delivery..." -ForegroundColor Gray

    if (-not $TeamsWebhook) {
        Write-Host "  ERROR: Teams webhook URL not provided" -ForegroundColor Red
        Write-Host "  Set -TeamsWebhook parameter or SDM_TEAMS_WEBHOOK environment variable" -ForegroundColor Red
        $results.Teams = @{
            Success = $false
            Message = "Webhook URL not provided"
        }
        $hasFailure = $true
    }
    else {
        $teamsResult = Send-TeamsNotification -WebhookUrl $TeamsWebhook

        if ($teamsResult.Success) {
            Write-Host "  Teams: SUCCESS" -ForegroundColor Green
        }
        else {
            Write-Host "  Teams: FAILED - $($teamsResult.Message)" -ForegroundColor Red
            $hasFailure = $true
        }

        $results.Teams = $teamsResult
    }

    Write-Host ""
}

# Test Email if requested
if ($Channel -eq "Email" -or $Channel -eq "Both") {
    Write-Host "Testing Email delivery..." -ForegroundColor Gray

    if (-not $EmailRecipient) {
        Write-Host "  ERROR: Email recipient not provided" -ForegroundColor Red
        Write-Host "  Set -EmailRecipient parameter or SDM_NOTIFICATION_EMAIL environment variable" -ForegroundColor Red
        $results.Email = @{
            Success = $false
            Message = "Email recipient not provided"
        }
        $hasFailure = $true
    }
    elseif (-not $FromEmail) {
        Write-Host "  ERROR: From email not provided" -ForegroundColor Red
        Write-Host "  Set -FromEmail parameter or SDM_FROM_EMAIL environment variable" -ForegroundColor Red
        $results.Email = @{
            Success = $false
            Message = "From email not provided"
        }
        $hasFailure = $true
    }
    elseif (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users.Actions)) {
        Write-Host "  ERROR: Microsoft.Graph.Users.Actions module not installed" -ForegroundColor Red
        Write-Host "  Install with: Install-Module Microsoft.Graph.Users.Actions -Scope CurrentUser" -ForegroundColor Red
        $results.Email = @{
            Success = $false
            Message = "Microsoft.Graph.Users.Actions module not installed"
        }
        $hasFailure = $true
    }
    elseif (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Host "  ERROR: Microsoft.Graph.Authentication module not installed" -ForegroundColor Red
        Write-Host "  Install with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser" -ForegroundColor Red
        $results.Email = @{
            Success = $false
            Message = "Microsoft.Graph.Authentication module not installed"
        }
        $hasFailure = $true
    }
    else {
        $emailResult = Send-EmailNotification `
            -To $EmailRecipient `
            -From $FromEmail

        if ($emailResult.Success) {
            Write-Host "  Email: SUCCESS" -ForegroundColor Green
        }
        else {
            Write-Host "  Email: FAILED - $($emailResult.Message)" -ForegroundColor Red
            $hasFailure = $true
        }

        $results.Email = $emailResult
    }

    Write-Host ""
}

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($results.Teams) {
    $teamsStatus = if ($results.Teams.Success) { "PASS" } else { "FAIL" }
    $teamsColor = if ($results.Teams.Success) { "Green" } else { "Red" }
    Write-Host "Teams: " -NoNewline
    Write-Host $teamsStatus -ForegroundColor $teamsColor
}

if ($results.Email) {
    $emailStatus = if ($results.Email.Success) { "PASS" } else { "FAIL" }
    $emailColor = if ($results.Email.Success) { "Green" } else { "Red" }
    Write-Host "Email: " -NoNewline
    Write-Host $emailStatus -ForegroundColor $emailColor
}

Write-Host ""

# Return results object
$output = [PSCustomObject]@{
    TestTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Channel  = $Channel
    Results  = $results
    Success  = (-not $hasFailure)
}

Write-Output $output

# Exit with appropriate code
if ($hasFailure) {
    exit 1
}
else {
    exit 0
}

#endregion
