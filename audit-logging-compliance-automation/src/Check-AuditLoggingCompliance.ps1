#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Microsoft.PowerApps.Administration.PowerShell"; ModuleVersion="2.0.0" }
#Requires -Modules @{ ModuleName="ExchangeOnlineManagement"; ModuleVersion="3.0.0" }

<#
.SYNOPSIS
    Azure Automation detection runbook for audit logging compliance across Power Platform environments.

.DESCRIPTION
    Scans all Power Platform environments for Purview unified audit and Dataverse audit
    compliance. Authenticates via System-Assigned Managed Identity. Writes compliance
    results to Dataverse via upsert pattern. Optionally sends HTML email notification
    with CSV attachment.

    Detection logic:
    - Dataverse environments: require BOTH Purview unified audit AND Dataverse org-level audit
    - Non-Dataverse environments: require Purview unified audit only
    - Validates recent audit events via Search-UnifiedAuditLog (last 7 days)

    This runbook NEVER uses interactive authentication or hardcoded credentials.

.PARAMETER DataverseEnvironmentUrl
    Mandatory. The Dataverse environment URL hosting the fsi_auditenvironmentcompliance table.
    Example: https://governance.crm.dynamics.com

.PARAMETER TenantDomain
    Mandatory. The tenant domain for Exchange Online authentication.
    Example: contoso.onmicrosoft.com

.PARAMETER NotificationFromAddress
    Optional. Shared mailbox email address for sending notifications.
    Example: powerplatform-governance@contoso.com

.PARAMETER NotificationToAddresses
    Optional. Comma-separated list of notification recipients.
    Example: "admin@contoso.com,compliance@contoso.com"

.PARAMETER SendEmail
    Optional switch. When set, sends an HTML email notification with compliance summary
    and CSV attachment. Requires NotificationFromAddress and NotificationToAddresses.

.EXAMPLE
    .\Check-AuditLoggingCompliance.ps1 `
        -DataverseEnvironmentUrl "https://governance.crm.dynamics.com" `
        -TenantDomain "contoso.onmicrosoft.com"

    Scans all environments and writes results to Dataverse. No email notification.

.EXAMPLE
    .\Check-AuditLoggingCompliance.ps1 `
        -DataverseEnvironmentUrl "https://governance.crm.dynamics.com" `
        -TenantDomain "contoso.onmicrosoft.com" `
        -SendEmail `
        -NotificationFromAddress "governance@contoso.com" `
        -NotificationToAddresses "admin@contoso.com,compliance@contoso.com"

    Scans all environments, writes to Dataverse, and sends email with CSV attachment.

.NOTES
    Version: 1.0.0
    Requires: Azure Automation with System-Assigned Managed Identity
    Permissions: Power Platform Administrator, Exchange Administrator, Dataverse Application User, Mail.Send
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseEnvironmentUrl,

    [Parameter(Mandatory = $true)]
    [string]$TenantDomain,

    [Parameter(Mandatory = $false)]
    [string]$NotificationFromAddress,

    [Parameter(Mandatory = $false)]
    [string]$NotificationToAddresses,

    [Parameter(Mandatory = $false)]
    [switch]$SendEmail
)

$ErrorActionPreference = "Stop"

# Import helper module from same directory
$modulePath = Join-Path $PSScriptRoot "AuditComplianceHelpers.psm1"
Import-Module $modulePath -Force -ErrorAction Stop

# --- Step 1: Authenticate ---

Write-Output "================================================================"
Write-Output "  Audit Logging Compliance Check"
Write-Output "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC' -AsUTC)"
Write-Output "================================================================"
Write-Output ""

Write-Output "[Step 1/6] Authenticating via Managed Identity..."

try {
    # Authenticate to Power Platform
    $ppToken = Get-ManagedIdentityToken -Resource "https://api.bap.microsoft.com/"
    Add-PowerAppsAccount -Endpoint prod -TenantID $TenantDomain -ApplicationId $null -AccessToken $ppToken
    Write-Output "  [OK] Power Platform authentication successful"
}
catch {
    Write-Output "  [FATAL] Power Platform authentication failed: $($_.Exception.Message)"
    throw
}

try {
    # Authenticate to Exchange Online
    Connect-ExchangeOnline -ManagedIdentity -Organization $TenantDomain -ShowBanner:$false -ErrorAction Stop
    Write-Output "  [OK] Exchange Online authentication successful"
}
catch {
    Write-Output "  [FATAL] Exchange Online authentication failed: $($_.Exception.Message)"
    throw
}

try {
    # Get Dataverse token for compliance record writes
    $dvToken = Get-DataverseToken -DataverseEnvironmentUrl $DataverseEnvironmentUrl
    Write-Output "  [OK] Dataverse authentication successful"
}
catch {
    Write-Output "  [FATAL] Dataverse authentication failed: $($_.Exception.Message)"
    throw
}

Write-Output ""

# --- Step 2: Enumerate Environments ---

Write-Output "[Step 2/6] Enumerating Power Platform environments..."

try {
    $environments = Get-AdminPowerAppEnvironment -ErrorAction Stop
    $envCount = ($environments | Measure-Object).Count
    Write-Output "  [OK] Found $envCount environment(s)"
}
catch {
    Write-Output "  [FATAL] Environment enumeration failed: $($_.Exception.Message)"
    throw
}

Write-Output ""

# --- Step 3/4/5: Scan Each Environment ---

Write-Output "[Step 3/6] Scanning environments for audit compliance..."
Write-Output ""

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$envIndex = 0
$compliantCount = 0
$nonCompliantCount = 0
$errorCount = 0

try {
    foreach ($env in $environments) {
        $envIndex++
        $envId = $env.EnvironmentName  # GUID
        $envDisplayName = $env.DisplayName
        $hasDataverse = ($null -ne $env.Internal.Properties.LinkedEnvironmentMetadata)

        Write-Output "  [$envIndex/$envCount] $envDisplayName ($envId)"
        Write-Output "           Dataverse provisioned: $hasDataverse"

        try {
            # --- Check Purview Unified Audit ---
            $purviewEnabled = $false
            try {
                $adminConfig = Get-AdminConfig -EnvironmentName $envId -ErrorAction Stop
                $purviewEnabled = [bool]$adminConfig.UnifiedAuditLogIngestionEnabled
            }
            catch {
                Write-Verbose "  Could not retrieve admin config for $envId : $($_.Exception.Message)"
            }
            Write-Output "           Purview unified audit: $purviewEnabled"

            # --- Check Dataverse Audit (if Dataverse provisioned) ---
            $dataverseAuditEnabled = $false
            if ($hasDataverse) {
                try {
                    $orgUrl = $env.Internal.Properties.LinkedEnvironmentMetadata.InstanceApiUrl
                    if ($orgUrl) {
                        $orgUrl = $orgUrl.TrimEnd('/')
                        $dvEnvToken = Get-ManagedIdentityToken -Resource $orgUrl

                        $orgResponse = Invoke-DataverseRequest `
                            -EnvironmentUrl $orgUrl `
                            -RelativeUri "/api/data/v9.2/organizations?`$select=isauditenabled,organizationid" `
                            -Token $dvEnvToken `
                            -Method GET

                        if ($orgResponse.value -and $orgResponse.value.Count -gt 0) {
                            $dataverseAuditEnabled = [bool]$orgResponse.value[0].isauditenabled
                        }
                    }
                }
                catch {
                    Write-Verbose "  Could not check Dataverse audit for $envId : $($_.Exception.Message)"
                }
            }
            Write-Output "           Dataverse audit enabled: $(if ($hasDataverse) { $dataverseAuditEnabled } else { 'N/A' })"

            # --- Validate Recent Audit Events ---
            $lastEvent = $null
            try {
                $startDate = (Get-Date).AddDays(-7)
                $endDate = Get-Date
                $auditResults = Search-UnifiedAuditLog `
                    -StartDate $startDate `
                    -EndDate $endDate `
                    -RecordType "PowerAppsApp", "PowerAppsPlan", "PowerAppsResource" `
                    -ResultSize 1 `
                    -ErrorAction SilentlyContinue

                if ($auditResults) {
                    $lastEvent = ($auditResults | Select-Object -First 1).CreationDate
                }
            }
            catch {
                Write-Verbose "  Audit event search failed for $envId : $($_.Exception.Message)"
            }
            Write-Output "           Last audit event: $(if ($lastEvent) { $lastEvent.ToString('yyyy-MM-dd HH:mm') } else { 'None in last 7 days' })"

            # --- Determine Compliance ---
            $complianceStatus = "Non-Compliant"
            if ($hasDataverse) {
                # Dataverse environments require BOTH
                if ($purviewEnabled -and $dataverseAuditEnabled) {
                    $complianceStatus = "Compliant"
                }
            }
            else {
                # Non-Dataverse environments require Purview only
                if ($purviewEnabled) {
                    $complianceStatus = "Compliant"
                }
            }

            Write-Output "           Compliance status: $complianceStatus"
            Write-Output ""

            # Track counts
            if ($complianceStatus -eq "Compliant") { $compliantCount++ }
            else { $nonCompliantCount++ }

            # --- Write to Dataverse ---
            $writeParams = @{
                EnvironmentUrl       = $DataverseEnvironmentUrl
                Token                = $dvToken
                EnvironmentId        = $envId
                EnvironmentName      = $envDisplayName
                AuditEnabled         = $purviewEnabled
                DataverseAuditEnabled = $dataverseAuditEnabled
                ComplianceStatus     = $complianceStatus
            }
            if ($lastEvent) {
                $writeParams.LastEventCaptured = $lastEvent
            }

            Write-DataverseComplianceRecord @writeParams | Out-Null

            # Collect result for CSV/email
            $results.Add([PSCustomObject]@{
                EnvironmentId        = $envId
                EnvironmentName      = $envDisplayName
                DataverseProvisioned = $hasDataverse
                PurviewAuditEnabled  = $purviewEnabled
                DataverseAuditEnabled = $dataverseAuditEnabled
                LastAuditEvent       = if ($lastEvent) { $lastEvent.ToString("o") } else { "" }
                ComplianceStatus     = $complianceStatus
                ErrorMessage         = ""
                CheckedAt            = (Get-Date -AsUTC -Format "o")
            })
        }
        catch {
            # Per-environment error — record and continue
            $errorCount++
            $errorMsg = $_.Exception.Message
            Write-Output "           [ERROR] $errorMsg"
            Write-Output ""

            # Write error record to Dataverse
            try {
                Write-DataverseComplianceRecord `
                    -EnvironmentUrl $DataverseEnvironmentUrl `
                    -Token $dvToken `
                    -EnvironmentId $envId `
                    -EnvironmentName $envDisplayName `
                    -AuditEnabled $false `
                    -DataverseAuditEnabled $false `
                    -ComplianceStatus "Error" `
                    -ErrorMessage $errorMsg | Out-Null
            }
            catch {
                Write-Verbose "  Failed to write error record for $envId : $($_.Exception.Message)"
            }

            $results.Add([PSCustomObject]@{
                EnvironmentId        = $envId
                EnvironmentName      = $envDisplayName
                DataverseProvisioned = $hasDataverse
                PurviewAuditEnabled  = $false
                DataverseAuditEnabled = $false
                LastAuditEvent       = ""
                ComplianceStatus     = "Error"
                ErrorMessage         = $errorMsg
                CheckedAt            = (Get-Date -AsUTC -Format "o")
            })
        }
    }

    # --- Step 4: Export CSV ---

    Write-Output "[Step 4/6] Exporting results to CSV..."

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $csvPath = Join-Path $env:TEMP "AuditCompliance-$timestamp.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Output "  [OK] CSV exported to: $csvPath"
    Write-Output ""

    # --- Step 5: Compliance Summary ---

    Write-Output "[Step 5/6] Compliance Summary"
    Write-Output "================================================================"
    Write-Output "  Total environments:  $envCount"
    Write-Output "  Compliant:           $compliantCount"
    Write-Output "  Non-Compliant:       $nonCompliantCount"
    Write-Output "  Errors:              $errorCount"
    Write-Output "================================================================"
    Write-Output ""

    # --- Step 6: Email Notification (optional) ---

    if ($SendEmail) {
        Write-Output "[Step 6/6] Sending email notification..."

        if (-not $NotificationFromAddress -or -not $NotificationToAddresses) {
            Write-Output "  [SKIP] Email requested but NotificationFromAddress or NotificationToAddresses not provided"
        }
        else {
            $toAddresses = $NotificationToAddresses -split ',' | ForEach-Object { $_.Trim() }

            # Build HTML email body
            $htmlBody = @"
<html>
<head>
<style>
    body { font-family: Segoe UI, Arial, sans-serif; }
    table { border-collapse: collapse; width: 100%; margin-top: 16px; }
    th { background-color: #0078D4; color: white; padding: 8px 12px; text-align: left; }
    td { padding: 8px 12px; border-bottom: 1px solid #E0E0E0; }
    .compliant { color: #107C10; font-weight: bold; }
    .non-compliant { color: #D83B01; font-weight: bold; }
    .error { color: #A80000; font-weight: bold; }
    .summary { background-color: #F3F3F3; padding: 16px; border-radius: 4px; margin-bottom: 16px; }
</style>
</head>
<body>
<h2>Audit Logging Compliance Report</h2>
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC' -AsUTC)</p>

<div class="summary">
    <strong>Summary:</strong> $envCount environment(s) scanned &mdash;
    <span class="compliant">$compliantCount compliant</span>,
    <span class="non-compliant">$nonCompliantCount non-compliant</span>,
    <span class="error">$errorCount error(s)</span>
</div>

<table>
<tr>
    <th>Environment</th>
    <th>Dataverse</th>
    <th>Purview Audit</th>
    <th>Dataverse Audit</th>
    <th>Last Event</th>
    <th>Status</th>
</tr>
$(
    $results | ForEach-Object {
        $statusClass = switch ($_.ComplianceStatus) {
            'Compliant' { 'compliant' }
            'Non-Compliant' { 'non-compliant' }
            'Error' { 'error' }
            default { '' }
        }
        $lastEvt = if ($_.LastAuditEvent) { ([datetime]$_.LastAuditEvent).ToString('yyyy-MM-dd HH:mm') } else { 'N/A' }
        "<tr><td>$($_.EnvironmentName)</td><td>$($_.DataverseProvisioned)</td><td>$($_.PurviewAuditEnabled)</td><td>$($_.DataverseAuditEnabled)</td><td>$lastEvt</td><td class='$statusClass'>$($_.ComplianceStatus)</td></tr>"
    }
)
</table>

<p><em>Full details are attached as CSV.</em></p>
<p style="color: #666; font-size: 12px;">This is an automated notification from the Audit Logging Compliance Automation (ALCA) solution.</p>
</body>
</html>
"@

            try {
                Send-ComplianceNotification `
                    -FromAddress $NotificationFromAddress `
                    -ToAddresses $toAddresses `
                    -Subject "Audit Logging Compliance Report — $compliantCount/$envCount Compliant" `
                    -HtmlBody $htmlBody `
                    -AttachmentPath $csvPath `
                    -AttachmentName "AuditCompliance-$timestamp.csv"

                Write-Output "  [OK] Email sent to: $($toAddresses -join ', ')"
            }
            catch {
                Write-Output "  [ERROR] Failed to send email: $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Output "[Step 6/6] Email notification: Skipped (use -SendEmail to enable)"
    }
}
finally {
    # --- Cleanup: Disconnect sessions ---
    Write-Output ""
    Write-Output "Disconnecting sessions..."

    try {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Write-Output "  [OK] Exchange Online disconnected"
    }
    catch {
        Write-Verbose "Exchange Online disconnect failed: $($_.Exception.Message)"
    }

    try {
        Remove-PowerAppsAccount -ErrorAction SilentlyContinue
        Write-Output "  [OK] Power Platform disconnected"
    }
    catch {
        Write-Verbose "Power Platform disconnect failed: $($_.Exception.Message)"
    }

    Write-Output ""
    Write-Output "Audit compliance check complete."
}
