#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users.Actions

<#
.SYNOPSIS
    Sends pipeline governance notifications to environment owners via Microsoft Graph.

.DESCRIPTION
    Reads a pipeline inventory CSV and sends email notifications to owners about
    upcoming governance actions. Uses Microsoft Graph API for email delivery.

    This script complements the Get-PipelineInventory.ps1 script. After reviewing
    the inventory and identifying non-compliant pipelines (manual process), use
    this script to notify affected owners.

.PARAMETER InputPath
    Path to the CSV file containing pipeline/environment records with owner information.

.PARAMETER EnforcementDate
    Date when enforcement actions will be taken. Displayed in notification emails.

.PARAMETER TestMode
    If specified, outputs email content to console instead of sending.

.PARAMETER SupportEmail
    Email address for the Platform Operations team. Included in notifications.

.PARAMETER MigrationUrl
    URL for the migration request form or documentation. Must use https://.

.PARAMETER ExemptionUrl
    URL for the exemption request form. Must use https://.

.PARAMETER Force
    If specified, allows sending even when placeholder defaults are detected.
    Without this switch, the script blocks in production mode when default
    SupportEmail, MigrationUrl, or ExemptionUrl values are unchanged.

.EXAMPLE
    .\Send-OwnerNotifications.ps1 -InputPath ".\inventory.csv" -EnforcementDate "2026-03-01" -TestMode

.EXAMPLE
    .\Send-OwnerNotifications.ps1 -InputPath ".\non-compliant.csv" -EnforcementDate "2026-03-01" -SupportEmail "platform-ops@contoso.com"

.NOTES
    Prerequisites:
    - Microsoft Graph PowerShell SDK
    - Mail.Send permission (delegated or application)

    Authentication modes:
    - Delegated (default): Uses interactive sign-in, sends as signed-in user
    - Application: Requires -SenderEmail parameter, sends as specified user

    The input CSV must contain these columns:
    - OwnerEmail: Email address of the owner to notify
    - EnvironmentName: Name of the environment/pipeline
    - EnvironmentId: Environment GUID

    IMPORTANT: Review your inventory and filter to non-compliant items before
    running notifications. This script does not determine compliance status.
#>

[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'PSScriptAnalyzer honors this rule at script or function scope; flagged compatibility parameters below include individual justifications.'
)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [datetime]$EnforcementDate,

    [Parameter(Mandatory = $false)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [switch]$TestMode,

    [Parameter(Mandatory = $false)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [string]$SupportEmail = "platform-ops@example.com",

    [Parameter(Mandatory = $false)]
    [ValidateScript({ $_ -match '^https://' })]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [string]$MigrationUrl = "https://company.service-now.com/pipeline-migration",

    [Parameter(Mandatory = $false)]
    [ValidateScript({ $_ -match '^https://' })]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [string]$ExemptionUrl = "https://company.service-now.com/pipeline-exemption",

    [Parameter(Mandatory = $false)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [string]$SenderEmail = "",

    [Parameter(Mandatory = $false)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [switch]$Force
)

# Build email body from template
function Build-NotificationEmail {
    param(
        [string]$OwnerName,
        [string]$EnvironmentName,
        [string]$EnvironmentId,
        [datetime]$EnforcementDate,
        [string]$SupportEmail,
        [string]$MigrationUrl,
        [string]$ExemptionUrl
    )

    $formattedDate = $EnforcementDate.ToString("MMMM d, yyyy")

    # HTML-encode interpolated values to prevent malformed HTML
    $safeOwnerName = [System.Net.WebUtility]::HtmlEncode($OwnerName)
    $safeEnvironmentName = [System.Net.WebUtility]::HtmlEncode($EnvironmentName)
    $safeEnvironmentId = [System.Net.WebUtility]::HtmlEncode($EnvironmentId)
    $safeSupportEmail = [System.Net.WebUtility]::HtmlEncode($SupportEmail)
    $safeMigrationUrl = [System.Net.WebUtility]::HtmlEncode($MigrationUrl)
    $safeExemptionUrl = [System.Net.WebUtility]::HtmlEncode($ExemptionUrl)

    $body = @"
<html>
<body style="font-family: Segoe UI, Arial, sans-serif; line-height: 1.6; color: #333;">
<p>Dear $safeOwnerName,</p>

<p>As part of our Power Platform governance initiative, we are consolidating all deployment pipelines to our designated pipelines host environment.</p>

<table style="border-collapse: collapse; margin: 20px 0;">
<tr>
    <td style="padding: 8px; border: 1px solid #ddd; background: #f5f5f5;"><strong>Environment:</strong></td>
    <td style="padding: 8px; border: 1px solid #ddd;">$safeEnvironmentName</td>
</tr>
<tr>
    <td style="padding: 8px; border: 1px solid #ddd; background: #f5f5f5;"><strong>Environment ID:</strong></td>
    <td style="padding: 8px; border: 1px solid #ddd; font-family: monospace;">$safeEnvironmentId</td>
</tr>
<tr>
    <td style="padding: 8px; border: 1px solid #ddd; background: #f5f5f5;"><strong>Action Required By:</strong></td>
    <td style="padding: 8px; border: 1px solid #ddd; color: #c00;"><strong>$formattedDate</strong></td>
</tr>
</table>

<p><strong>What This Means:</strong></p>
<p>Pipelines in this environment were created outside of our centrally governed infrastructure. To maintain compliance with our IT governance policies, all deployment pipelines must use the designated pipelines host environment.</p>

<p><strong>Your Options:</strong></p>

<ol>
<li><strong>Migrate to Central Host (Recommended)</strong>
    <ul>
        <li>Contact the Platform Ops team to migrate your pipelines</li>
        <li>Your deployed solutions will remain in place</li>
        <li>Pipeline definitions must be recreated in the central host</li>
        <li>Request via: <a href="$safeMigrationUrl">Migration Request Form</a></li>
    </ul>
</li>
<li><strong>Request Exemption</strong>
    <ul>
        <li>If you have a business justification, submit an exemption request</li>
        <li>Exemptions require approval from the Agent Governance Committee</li>
        <li>Request via: <a href="$safeExemptionUrl">Exemption Request Form</a></li>
    </ul>
</li>
<li><strong>No Action Needed</strong>
    <ul>
        <li>If you no longer need the pipelines in this environment, no action is required</li>
        <li>The environment will be force-linked to the central host on $formattedDate</li>
    </ul>
</li>
</ol>

<p><strong>Questions?</strong></p>
<p>Contact the Platform Operations team at <a href="mailto:$safeSupportEmail">$safeSupportEmail</a>.</p>

<p>Thank you for your cooperation in maintaining our governance standards.</p>

<p>Best regards,<br>
<strong>Platform Operations Team</strong></p>

<hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;">
<p style="font-size: 12px; color: #666;">
This is an automated notification from the Pipeline Governance system.
Environment ID: $safeEnvironmentId
</p>
</body>
</html>
"@

    return $body
}

# Send email via Microsoft Graph
function Send-GraphEmail {
    [CmdletBinding()]
    param(
        [string]$To,
        [string]$Subject,
        [string]$Body,
        [string]$Sender = ""
    )

    $message = @{
        message = @{
            subject = $Subject
            body = @{
                contentType = "HTML"
                content = $Body
            }
            toRecipients = @(
                @{
                    emailAddress = @{
                        address = $To
                    }
                }
            )
        }
        saveToSentItems = $true
    }

    # Determine UserId: explicit sender for application permissions; signed-in account for delegated.
    # Send-MgUserMail does NOT accept the literal "me" alias — the underlying Graph route is
    # /users/{id|upn}/sendMail, which rejects "me". Fall back to the authenticated principal.
    if ([string]::IsNullOrEmpty($Sender)) {
        $ctx = Get-MgContext
        if ($null -eq $ctx -or [string]::IsNullOrEmpty($ctx.Account)) {
            Write-Error "No -SenderEmail provided and no signed-in delegated account on Microsoft Graph context."
            return $false
        }
        $userId = $ctx.Account
    }
    else {
        $userId = $Sender
    }

    $maxRetries = 3
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            Send-MgUserMail -UserId $userId -BodyParameter $message -ErrorAction Stop
            return $true
        }
        catch {
            # Inspect HTTP status code on the response (preferred) and Retry-After if present;
            # fall back to message regex for non-Graph SDK exceptions.
            $statusCode = $null
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
            $retryAfter = $null
            try { $retryAfter = $_.Exception.Response.Headers['Retry-After'] } catch { }

            $isTransient = (
                ($statusCode -in @(408, 429, 500, 502, 503, 504)) -or
                ($_.Exception.GetType().Name -match 'HttpRequestException|TaskCanceledException') -or
                ($_.Exception.Message -match '\b(429|503|504|timeout|throttl)\b')
            )
            if ($isTransient -and $attempt -lt $maxRetries) {
                $backoffSeconds = if ($retryAfter -and [int]::TryParse($retryAfter, [ref]$null)) {
                    [int]$retryAfter
                } else {
                    [Math]::Pow(2, $attempt)
                }
                Write-Warning "Transient error sending to $To (status=$statusCode, attempt $attempt/$maxRetries). Retrying in ${backoffSeconds}s..."
                Start-Sleep -Seconds $backoffSeconds
            }
            else {
                Write-Error "Failed to send email to $To (status=$statusCode): $_"
                return $false
            }
        }
    }
}

# Main execution
function Main {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  Pipeline Governance Notification Script" -ForegroundColor Cyan
    Write-Host "  Version: 1.1.0 - April 2026" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""

    # Check for placeholder defaults — block in production mode unless -Force
    $placeholderDefaults = @()
    if ($SupportEmail -eq "platform-ops@example.com") { $placeholderDefaults += "SupportEmail" }
    if ($MigrationUrl -eq "https://company.service-now.com/pipeline-migration") { $placeholderDefaults += "MigrationUrl" }
    if ($ExemptionUrl -eq "https://company.service-now.com/pipeline-exemption") { $placeholderDefaults += "ExemptionUrl" }

    if ($placeholderDefaults.Count -gt 0) {
        $paramList = $placeholderDefaults -join ", "
        if (-not $TestMode -and -not $Force) {
            Write-Error @"
BLOCKED: Placeholder default values detected for: $paramList

These defaults contain example URLs and email addresses that must be replaced
with your organization's actual values before sending notifications to owners.

To fix: Provide your organization's values:
  -SupportEmail "your-team@yourcompany.com"
  -MigrationUrl "https://your-itsm.com/migrate"
  -ExemptionUrl "https://your-itsm.com/exempt"

To override (not recommended): Use -Force to send with placeholder values.
To preview safely: Use -TestMode to see what would be sent.
"@
            exit 1
        }
        Write-Warning "Placeholder defaults detected for: $paramList. Review before production use."
    }

    # Load input data
    Write-Host "Loading inventory from: $InputPath" -ForegroundColor Cyan
    try {
        $records = Import-Csv -Path $InputPath -Encoding UTF8
        Write-Host "Loaded $($records.Count) records" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to load CSV: $_"
        exit 1
    }

    # Check for empty CSV
    if ($records.Count -eq 0) {
        Write-Warning "Input CSV is empty. No notifications to send."
        exit 0
    }

    # Validate required columns
    $requiredColumns = @("OwnerEmail", "EnvironmentName", "EnvironmentId")
    $missingColumns = $requiredColumns | Where-Object { $_ -notin $records[0].PSObject.Properties.Name }

    if ($missingColumns.Count -gt 0) {
        Write-Error @"
Input CSV is missing required columns: $($missingColumns -join ", ")

Required columns:
- OwnerEmail: Email address of the owner to notify
- EnvironmentName: Name of the environment
- EnvironmentId: Environment GUID

You may need to manually add owner information to your inventory before sending notifications.
"@
        exit 1
    }

    # Filter to records with valid email addresses
    $validRecords = $records | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.OwnerEmail) -and
        $_.OwnerEmail -match '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    }

    if ($validRecords.Count -eq 0) {
        Write-Warning "No records with valid email addresses found. Ensure OwnerEmail column contains valid addresses."
        exit 0
    }

    Write-Host "Records with valid email addresses: $($validRecords.Count)" -ForegroundColor Cyan
    Write-Host "Enforcement Date: $($EnforcementDate.ToString('MMMM d, yyyy'))" -ForegroundColor Cyan
    Write-Host ""

    # Connect to Microsoft Graph if not in test mode
    if (-not $TestMode) {
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
        if (-not [string]::IsNullOrEmpty($SenderEmail)) {
            Write-Host "Using application permissions with sender: $SenderEmail" -ForegroundColor Yellow
            Write-Host "Note: Ensure you have connected with application credentials before running this script." -ForegroundColor Yellow
        }
        if ([string]::IsNullOrEmpty($SenderEmail)) {
            try {
                Connect-MgGraph -Scopes "Mail.Send" -NoWelcome -ErrorAction Stop
                Write-Host "Connected to Microsoft Graph" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to connect to Microsoft Graph: $_"
                Write-Host "Run with -TestMode to preview emails without sending."
                exit 1
            }
        }
        else {
            Write-Host "Skipping Connect-MgGraph: using pre-existing application credentials connection." -ForegroundColor Green
        }
    }
    else {
        Write-Host "TEST MODE - Emails will be displayed but not sent" -ForegroundColor Yellow
        Write-Host ""
    }

    # Process records
    $sent = 0
    $failed = 0
    $index = 0
    $auditLog = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        foreach ($record in $validRecords) {
            $index++
            Write-Progress -Activity "Sending notifications" -Status "$index of $($validRecords.Count): $($record.OwnerEmail)" -PercentComplete (($index / $validRecords.Count) * 100)

            # Build email
            $ownerName = if ($record.OwnerName) { $record.OwnerName } else { "Pipeline Owner" }
            $subject = "Action Required: Pipeline Governance - $($record.EnvironmentName) - Action by $($EnforcementDate.ToString('MMM d'))"
            $body = Build-NotificationEmail -OwnerName $ownerName `
                                            -EnvironmentName $record.EnvironmentName `
                                            -EnvironmentId $record.EnvironmentId `
                                            -EnforcementDate $EnforcementDate `
                                            -SupportEmail $SupportEmail `
                                            -MigrationUrl $MigrationUrl `
                                            -ExemptionUrl $ExemptionUrl

            $status = "Skipped"

            if ($TestMode) {
                Write-Host "========================================" -ForegroundColor DarkGray
                Write-Host "TO: $($record.OwnerEmail)" -ForegroundColor White
                Write-Host "SUBJECT: $subject" -ForegroundColor White
                Write-Host "----------------------------------------" -ForegroundColor DarkGray
                Write-Host "Environment: $($record.EnvironmentName)"
                Write-Host "Environment ID: $($record.EnvironmentId)"
                Write-Host "Enforcement Date: $($EnforcementDate.ToString('MMMM d, yyyy'))"
                Write-Host "========================================" -ForegroundColor DarkGray
                Write-Host ""
                $sent++
                $status = "Previewed"
            }
            else {
                if ($PSCmdlet.ShouldProcess($record.OwnerEmail, "Send notification email")) {
                    $success = Send-GraphEmail -To $record.OwnerEmail -Subject $subject -Body $body -Sender $SenderEmail
                    if ($success) {
                        $sent++
                        $status = "Sent"
                        Write-Verbose "Sent notification to $($record.OwnerEmail)"
                    }
                    else {
                        $failed++
                        $status = "Failed"
                    }
                }
            }

            $auditLog.Add([PSCustomObject]@{
                Timestamp       = ([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"))
                Recipient       = $record.OwnerEmail
                EnvironmentId   = $record.EnvironmentId
                EnvironmentName = $record.EnvironmentName
                Subject         = $subject
                Status          = $status
            })
        }
    }
    finally {
        Write-Progress -Activity "Sending notifications" -Completed

        # Write audit log for compliance evidence (FINRA Rule 3110(a) / Rule 4511(a))
        $logTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $logDir = Split-Path -Path $InputPath -Parent
        if ([string]::IsNullOrEmpty($logDir)) { $logDir = "." }
        $logPath = Join-Path $logDir "NotificationLog_$logTimestamp.csv"

        if ($auditLog.Count -gt 0) {
            try {
                $auditLog | Export-Csv -Path $logPath -NoTypeInformation -Encoding UTF8
                Write-Host "Audit log written to: $logPath" -ForegroundColor Cyan
            }
            catch {
                Write-Warning "Failed to write audit log to $logPath — $($_.Exception.Message)"
            }
        }

        # Summary
        Write-Host ""
        Write-Host "================================================" -ForegroundColor Cyan
        Write-Host "  Notification Summary" -ForegroundColor Cyan
        Write-Host "================================================" -ForegroundColor Cyan
        if ($TestMode) {
            Write-Host "Test Mode: $sent email(s) previewed" -ForegroundColor Yellow
        }
        else {
            Write-Host "Sent: $sent" -ForegroundColor Green
            Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
        }
        Write-Host ""

        # Disconnect from Graph
        if (-not $TestMode) {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

# Run main function
Main
