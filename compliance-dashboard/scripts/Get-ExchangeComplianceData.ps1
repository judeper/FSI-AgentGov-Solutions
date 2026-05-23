<#
.SYNOPSIS
    Collects Exchange Online compliance signals via Microsoft Graph API.

.DESCRIPTION
    Gathers Exchange-related compliance data for the Compliance Dashboard,
    covering key risk areas for FSI environments where email is a primary
    vector for data leakage and regulatory exposure.

    Data collected:
    - External forwarding rules (data exfiltration risk)
    - DLP policy match alerts for Exchange workload
    - Inactive shared or disabled mailbox indicators
    - Distribution lists with external members
    - Security & Compliance PowerShell can be used separately for compliance search, eDiscovery, and retention policy evidence

    Output is a JSON evidence file compatible with the Compliance Dashboard's
    fsi_complianceevidence table for import via Power Automate or Dataverse API.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Defaults to AZURE_TENANT_ID environment variable.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID. Defaults to AZURE_CLIENT_ID environment variable.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.
    Mutually exclusive with -Interactive.

.PARAMETER Interactive
    Use interactive browser-based authentication.
    Mutually exclusive with -CertificateThumbprint.

.PARAMETER ConfigPath
    Path to exchange-config.json configuration file.
    Defaults to ../templates/exchange-config.sample.json relative to script.

.PARAMETER LookbackDays
    Number of days to look back for DLP alerts and activity data.
    Defaults to 30.

.PARAMETER OutputPath
    Path for the output JSON evidence file.
    Defaults to ./output/exchange-compliance-report.json.

.PARAMETER GraphBaseUrl
    Microsoft Graph API base URL. Supports sovereign clouds:
    https://graph.microsoft.com (commercial, default),
    https://graph.microsoft.us (GCC High),
    https://dod-graph.microsoft.us (DoD).

.PARAMETER AuthBaseUrl
    Microsoft Entra ID token endpoint base URL. Supports sovereign clouds:
    https://login.microsoftonline.com (commercial, default),
    https://login.microsoftonline.us (GCC High).

.EXAMPLE
    .\Get-ExchangeComplianceData.ps1 -Interactive

    Collects Exchange compliance data using interactive authentication.

.EXAMPLE
    .\Get-ExchangeComplianceData.ps1 -TenantId "tenant.onmicrosoft.com" -ClientId "00000000-0000-0000-0000-000000000001" -CertificateThumbprint "ABC123DEF456"

    Collects Exchange compliance data using certificate-based service principal auth.

.EXAMPLE
    .\Get-ExchangeComplianceData.ps1 -Interactive -LookbackDays 7 -OutputPath "./output/exchange-weekly.json"

    Weekly Exchange compliance snapshot with 7-day lookback.

.OUTPUTS
    JSON file with sections: ExternalForwarding, DLPAlerts, BroadMailboxAccess,
    ExternalDistributionListRisks, InactiveSharedMailboxes, Summary

.NOTES
    Version:    1.0.5
    Author:     FSI Agent Governance
    Requires:   PowerShell 7.0+
    Requires:   Microsoft.Graph.Authentication 2.0.0+
    Framework:  FSI Agent Governance
    Controls:   3.3, 3.1, 3.2, 3.4
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = "Microsoft.Graph.Authentication"; ModuleVersion = "2.0.0" }

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Interactive')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'PSScriptAnalyzer honors this rule at script or function scope; flagged compatibility parameters below include individual justifications.'
)]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false, ParameterSetName = 'ServicePrincipal')]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$LookbackDays = 30,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\output\exchange-compliance-report.json",

    [Parameter(Mandatory = $false)]
    [ValidateSet("https://graph.microsoft.com", "https://graph.microsoft.us", "https://dod-graph.microsoft.us")]
    [string]$GraphBaseUrl = "https://graph.microsoft.com",

    [Parameter(Mandatory = $false)]
    [ValidateSet("https://login.microsoftonline.com", "https://login.microsoftonline.us")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Required by the authentication parameter-set contract; the selected parameter set drives behavior in this implementation.'
    )]
    [string]$AuthBaseUrl = "https://login.microsoftonline.com"
)

$ErrorActionPreference = "Stop"
$script:CorrelationId = [guid]::NewGuid().ToString("N").Substring(0, 8)

#region Helpers

function Write-AuditLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        default   { "White" }
    }
    Write-Host "[$timestamp] [$Level] [$script:CorrelationId] $Message" -ForegroundColor $color
}

function Get-ExchangeConfig {
    param([string]$Path)

    $defaults = @{
        scanScope = @{
            includeUserMailboxes      = $true
            includeSharedMailboxes    = $true
            includeDistributionLists  = $true
            externalDomainAllowList   = @()
        }
        riskThresholds = @{
            externalForwardingRisk    = "HIGH"
            dlpMatchRisk              = "MEDIUM"
            broadMailboxAccessRisk    = "MEDIUM"
        }
        retentionDays = 30
    }

    if ($Path -and (Test-Path $Path)) {
        try {
            $fileConfig = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable
            foreach ($key in $fileConfig.Keys) {
                if ($key -ne "metadata") {
                    $defaults[$key] = $fileConfig[$key]
                }
            }
            Write-AuditLog "Loaded configuration from $Path"
        }
        catch {
            Write-AuditLog "Failed to parse config file '$Path': $($_.Exception.Message)" "WARN"
        }
    }

    return $defaults
}

function Invoke-GraphRequest {
    param(
        [string]$Uri,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [int]$MaxRetries = 3
    )

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            if ($Headers.Count -gt 0) {
                $response = Invoke-MgGraphRequest -Uri $Uri -Method $Method -Headers $Headers -OutputType PSObject
            }
            else {
                $response = Invoke-MgGraphRequest -Uri $Uri -Method $Method -OutputType PSObject
            }
            return $response
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            # Honor server-supplied Retry-After header on 429/503 when available.
            $retryAfterHeader = $null
            try { $retryAfterHeader = $_.Exception.Response.Headers['Retry-After'] } catch {}

            if ($statusCode -eq 429 -and $attempt -lt $MaxRetries) {
                $retryAfter = if ($retryAfterHeader -and [int]::TryParse($retryAfterHeader, [ref]$null)) {
                    [int]$retryAfterHeader
                } else { 60 * $attempt }
                Write-AuditLog "Throttled (429). Retrying in ${retryAfter}s (attempt $attempt/$MaxRetries)" "WARN"
                Start-Sleep -Seconds $retryAfter
            }
            elseif ($statusCode -in @(500, 502, 503, 504) -and $attempt -lt $MaxRetries) {
                $delay = if ($retryAfterHeader -and [int]::TryParse($retryAfterHeader, [ref]$null)) {
                    [int]$retryAfterHeader
                } else { [int]([math]::Pow(2, $attempt) * 5) }
                Write-AuditLog "Server error ($statusCode). Retrying in ${delay}s (attempt $attempt/$MaxRetries)" "WARN"
                Start-Sleep -Seconds $delay
            }
            else {
                throw
            }
        }
    }
}

function Invoke-GraphRequestWithPagination {
    param(
        [string]$Uri,
        [hashtable]$Headers = @{}
    )

    $results = [System.Collections.Generic.List[object]]::new()

    $nextLink = $Uri
    while ($nextLink) {
        $response = Invoke-GraphRequest -Uri $nextLink -Headers $Headers
        if ($response.value) {
            $results.AddRange([object[]]$response.value)
        }
        $nextLink = $response.'@odata.nextLink'
    }

    return $results
}

#endregion

#region Data Collection Functions

function Get-ExternalForwardingRules {
    param(
        [string]$GraphBase,
        [string[]]$AllowedDomains
    )

    Write-AuditLog "Scanning for external forwarding rules..."
    $findings = [System.Collections.Generic.List[hashtable]]::new()

    try {
        # `assignedLicenses/$count ne 0` is a Graph "advanced query" that requires the
        # `ConsistencyLevel: eventual` header alongside `$count=true`.
        $advHeaders = @{ ConsistencyLevel = 'eventual' }
        $users = Invoke-GraphRequestWithPagination -Uri "$GraphBase/v1.0/users?`$select=id,displayName,userPrincipalName,mail&`$filter=assignedLicenses/`$count ne 0&`$count=true&`$top=999" -Headers $advHeaders
    }
    catch {
        Write-AuditLog "Failed to list users: $($_.Exception.Message). Trying without filter..." "WARN"
        try {
            $users = Invoke-GraphRequestWithPagination -Uri "$GraphBase/v1.0/users?`$select=id,displayName,userPrincipalName,mail&`$top=999"
        }
        catch {
            Write-AuditLog "Failed to list users: $($_.Exception.Message)" "ERROR"
            return $findings
        }
    }

    Write-AuditLog "Checking $($users.Count) users for forwarding rules"
    $checkedCount = 0

    foreach ($user in $users) {
        $checkedCount++
        if ($checkedCount % 50 -eq 0) {
            Write-AuditLog "Checked $checkedCount/$($users.Count) users..."
        }

        try {
            $rules = Invoke-GraphRequestWithPagination -Uri "$GraphBase/v1.0/users/$($user.id)/mailFolders/inbox/messageRules?`$select=id,displayName,isEnabled,actions"
        }
        catch {
            continue
        }

        foreach ($rule in $rules) {
            if (-not $rule.isEnabled) { continue }

            $forwardAddresses = @()
            if ($rule.actions.forwardTo) {
                $forwardAddresses += $rule.actions.forwardTo
            }
            if ($rule.actions.forwardAsAttachmentTo) {
                $forwardAddresses += $rule.actions.forwardAsAttachmentTo
            }
            if ($rule.actions.redirectTo) {
                $forwardAddresses += $rule.actions.redirectTo
            }

            foreach ($recipient in $forwardAddresses) {
                $address = $recipient.emailAddress.address
                if (-not $address) { continue }

                $domain = ($address -split "@")[-1]
                $userDomain = ($user.userPrincipalName -split "@")[-1]

                # Skip internal forwarding and allowed domains
                if ($domain -ieq $userDomain) { continue }
                if ($AllowedDomains -and ($AllowedDomains -contains $domain)) { continue }

                $findings.Add(@{
                    UserId              = $user.id
                    UserDisplayName     = $user.displayName
                    UserPrincipalName   = $user.userPrincipalName
                    RuleName            = $rule.displayName
                    RuleId              = $rule.id
                    ForwardToAddress    = $address
                    ForwardToDomain     = $domain
                    ActionType          = if ($rule.actions.forwardTo) { "Forward" }
                                         elseif ($rule.actions.forwardAsAttachmentTo) { "ForwardAsAttachment" }
                                         else { "Redirect" }
                    Risk                = "HIGH"
                })
            }
        }
    }

    Write-AuditLog "Found $($findings.Count) external forwarding rules" $(if ($findings.Count -gt 0) { "WARN" } else { "SUCCESS" })
    return $findings
}

function Get-DLPAlerts {
    param(
        [string]$GraphBase,
        [int]$Days
    )

    Write-AuditLog "Collecting DLP alerts for Exchange workload (last $Days days)..."
    $findings = [System.Collections.Generic.List[hashtable]]::new()

    $sinceDate = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    try {
        $alerts = Invoke-GraphRequestWithPagination -Uri (
            "$GraphBase/v1.0/security/alerts_v2?" +
            "`$filter=category eq 'DataLossPrevention' and createdDateTime ge $sinceDate" +
            "&`$select=id,title,severity,status,createdDateTime,description" +
            "&`$top=999&`$orderby=createdDateTime desc"
        )

        foreach ($alert in $alerts) {
            $findings.Add(@{
                AlertId         = $alert.id
                Title           = $alert.title
                Severity        = $alert.severity
                Status          = $alert.status
                CreatedDateTime = $alert.createdDateTime
                Description     = if ($alert.description) { $alert.description.Substring(0, [math]::Min(500, $alert.description.Length)) } else { "" }
                Risk            = switch ($alert.severity) {
                    "high"      { "HIGH" }
                    "medium"    { "MEDIUM" }
                    "low"       { "LOW" }
                    default     { "MEDIUM" }
                }
            })
        }
    }
    catch {
        Write-AuditLog "Failed to collect DLP alerts: $($_.Exception.Message)" "WARN"
        Write-AuditLog "Verify the app has SecurityAlert.Read.All permission" "WARN"
    }

    Write-AuditLog "Found $($findings.Count) DLP alerts" $(if ($findings.Count -gt 0) { "WARN" } else { "SUCCESS" })
    return $findings
}

function Get-BroadMailboxAccess {
    param(
        [string]$GraphBase,
        [int]$InactiveDays
    )

    Write-AuditLog "Scanning for shared mailboxes with broad access..."
    $findings = [System.Collections.Generic.List[hashtable]]::new()

    try {
        # `mailboxSettings/userPurpose eq 'shared'` is also an advanced query and
        # requires the `ConsistencyLevel: eventual` header.
        $advHeaders = @{ ConsistencyLevel = 'eventual' }
        $sharedMailboxes = Invoke-GraphRequestWithPagination -Uri (
            "$GraphBase/v1.0/users?" +
            "`$select=id,displayName,userPrincipalName,mail,accountEnabled,signInActivity" +
            "&`$filter=mailboxSettings/userPurpose eq 'shared'" +
            "&`$count=true&`$top=999"
        ) -Headers $advHeaders
    }
    catch {
        Write-AuditLog "Shared mailbox filter not supported. Trying alternate approach..." "WARN"
        try {
            # Fallback: list users and check for shared mailbox indicators
            $sharedMailboxes = Invoke-GraphRequestWithPagination -Uri (
                "$GraphBase/v1.0/users?" +
                "`$select=id,displayName,userPrincipalName,mail,accountEnabled,signInActivity" +
                "&`$top=999"
            )
            # Filter to disabled accounts (common for shared mailboxes)
            $sharedMailboxes = $sharedMailboxes | Where-Object { $_.accountEnabled -eq $false -and $_.mail }
        }
        catch {
            Write-AuditLog "Failed to list mailboxes: $($_.Exception.Message)" "ERROR"
            return $findings
        }
    }

    Write-AuditLog "Evaluating $($sharedMailboxes.Count) shared/disabled mailboxes"

    $inactiveThreshold = (Get-Date).AddDays(-$InactiveDays).ToUniversalTime()

    foreach ($mailbox in $sharedMailboxes) {
        $lastSignIn = $null
        $isInactive = $false

        if ($mailbox.signInActivity -and $mailbox.signInActivity.lastSignInDateTime) {
            $lastSignIn = [datetime]$mailbox.signInActivity.lastSignInDateTime
            $isInactive = $lastSignIn -lt $inactiveThreshold
        }
        else {
            $isInactive = $true
        }

        if ($isInactive) {
            $findings.Add(@{
                MailboxId             = $mailbox.id
                DisplayName           = $mailbox.displayName
                UserPrincipalName     = $mailbox.userPrincipalName
                Mail                  = $mailbox.mail
                AccountEnabled        = $mailbox.accountEnabled
                LastSignIn            = if ($lastSignIn) { $lastSignIn.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { "Never" }
                DaysInactive          = if ($lastSignIn) { [int]((Get-Date) - $lastSignIn).TotalDays } else { -1 }
                Risk                  = "MEDIUM"
            })
        }
    }

    Write-AuditLog "Found $($findings.Count) inactive shared mailboxes" $(if ($findings.Count -gt 0) { "WARN" } else { "SUCCESS" })
    return $findings
}

function Get-ExternalDistributionListRisks {
    param(
        [string]$GraphBase,
        [string[]]$AllowedDomains
    )

    Write-AuditLog "Scanning distribution lists for external members..."
    $findings = [System.Collections.Generic.List[hashtable]]::new()

    try {
        # Get mail-enabled groups (distribution lists and mail-enabled security groups)
        $groups = Invoke-GraphRequestWithPagination -Uri (
            "$GraphBase/v1.0/groups?" +
            "`$filter=mailEnabled eq true" +
            "&`$select=id,displayName,mail,groupTypes,membershipRule" +
            "&`$top=999"
        )
    }
    catch {
        Write-AuditLog "Failed to list distribution groups: $($_.Exception.Message)" "ERROR"
        return $findings
    }

    Write-AuditLog "Checking $($groups.Count) mail-enabled groups for external members"
    $checkedCount = 0

    foreach ($group in $groups) {
        $checkedCount++
        if ($checkedCount % 25 -eq 0) {
            Write-AuditLog "Checked $checkedCount/$($groups.Count) groups..."
        }

        try {
            $members = Invoke-GraphRequestWithPagination -Uri (
                "$GraphBase/v1.0/groups/$($group.id)/members?" +
                "`$select=id,displayName,userPrincipalName,userType" +
                "&`$top=999"
            )
        }
        catch {
            continue
        }

        $externalMembers = @()
        foreach ($member in $members) {
            if ($member.userType -eq "Guest" -or
                ($member.userPrincipalName -and $member.userPrincipalName -match "#EXT#")) {
                $memberDomain = if ($member.userPrincipalName) {
                    ($member.userPrincipalName -replace ".*@", "" -replace "#EXT#.*", "")
                } else { "unknown" }

                if ($AllowedDomains -and ($AllowedDomains -contains $memberDomain)) { continue }

                $externalMembers += @{
                    MemberId            = $member.id
                    DisplayName         = $member.displayName
                    UserPrincipalName   = $member.userPrincipalName
                    Domain              = $memberDomain
                }
            }
        }

        if ($externalMembers.Count -gt 0) {
            $findings.Add(@{
                GroupId               = $group.id
                GroupDisplayName      = $group.displayName
                GroupMail             = $group.mail
                TotalMembers          = $members.Count
                ExternalMemberCount   = $externalMembers.Count
                ExternalMembers       = $externalMembers
                Risk                  = "MEDIUM"
            })
        }
    }

    Write-AuditLog "Found $($findings.Count) distribution lists with external members" $(if ($findings.Count -gt 0) { "WARN" } else { "SUCCESS" })
    return $findings
}

#endregion

#region Main Execution

try {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   Compliance Dashboard — Exchange Compliance Collector    ║" -ForegroundColor Cyan
    Write-Host "║   FSI Agent Governance Framework v1.0.5                  ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Load configuration
    $configFilePath = $ConfigPath
    if (-not $configFilePath) {
        $configFilePath = Join-Path (Split-Path $PSScriptRoot -Parent) "templates" "exchange-config.sample.json"
    }
    $config = Get-ExchangeConfig -Path $configFilePath

    if ($LookbackDays -ne 30) {
        $config.retentionDays = $LookbackDays
    }

    # Authenticate
    Write-AuditLog "Authenticating to Microsoft Graph..."
    if ($PSCmdlet.ParameterSetName -eq 'Interactive' -or $Interactive) {
        $scopes = @(
            "User.Read.All",
            "MailboxSettings.Read",
            "Mail.Read",
            "Group.Read.All",
            "SecurityAlert.Read.All",
            "AuditLog.Read.All"
        )
        Connect-MgGraph -Scopes $scopes -TenantId $TenantId -ErrorAction Stop | Out-Null
    }
    else {
        $cert = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop
        Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Certificate $cert -ErrorAction Stop | Out-Null
    }
    Write-AuditLog "Authenticated to Microsoft Graph" "SUCCESS"

    # Prepare output
    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        Write-AuditLog "Created output directory: $outputDir"
    }

    $report = @{
        metadata = @{
            correlationId   = $script:CorrelationId
            generatedAt     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            lookbackDays    = $config.retentionDays
            graphBaseUrl    = $GraphBaseUrl
            version         = "1.0.5"
            framework       = "FSI Agent Governance"
            controlReference = "3.3, 3.1, 3.2, 3.4"
        }
    }

    # Collect data
    if ($PSCmdlet.ShouldProcess("Exchange Online", "Collect compliance data")) {

        # 1. External Forwarding Rules
        Write-AuditLog "Step 1/4: External forwarding rules"
        $report.ExternalForwarding = Get-ExternalForwardingRules `
            -GraphBase $GraphBaseUrl `
            -AllowedDomains $config.scanScope.externalDomainAllowList

        # 2. DLP Alerts
        Write-AuditLog "Step 2/4: DLP policy match alerts"
        $report.DLPAlerts = Get-DLPAlerts `
            -GraphBase $GraphBaseUrl `
            -Days $config.retentionDays

        # 3. Broad Mailbox Access (inactive shared mailboxes)
        if ($config.scanScope.includeSharedMailboxes) {
            Write-AuditLog "Step 3/4: Shared mailbox access audit"
            $report.BroadMailboxAccess = Get-BroadMailboxAccess `
                -GraphBase $GraphBaseUrl `
                -InactiveDays $config.retentionDays
        }
        else {
            Write-AuditLog "Step 3/4: Shared mailbox scan skipped (disabled in config)" "WARN"
            $report.BroadMailboxAccess = @()
        }

        # 4. External Distribution List Risks
        if ($config.scanScope.includeDistributionLists) {
            Write-AuditLog "Step 4/4: Distribution list external membership"
            $report.ExternalDistributionListRisks = Get-ExternalDistributionListRisks `
                -GraphBase $GraphBaseUrl `
                -AllowedDomains $config.scanScope.externalDomainAllowList
        }
        else {
            Write-AuditLog "Step 4/4: Distribution list scan skipped (disabled in config)" "WARN"
            $report.ExternalDistributionListRisks = @()
        }

        # Summary
        $report.Summary = @{
            ExternalForwardingCount       = $report.ExternalForwarding.Count
            DLPAlertCount                 = $report.DLPAlerts.Count
            InactiveSharedMailboxCount    = $report.BroadMailboxAccess.Count
            ExternalDLMembershipCount    = $report.ExternalDistributionListRisks.Count
            HighRiskCount                 = (
                @($report.ExternalForwarding | Where-Object { $_.Risk -eq "HIGH" }).Count +
                @($report.DLPAlerts | Where-Object { $_.Risk -eq "HIGH" }).Count
            )
            MediumRiskCount               = (
                @($report.DLPAlerts | Where-Object { $_.Risk -eq "MEDIUM" }).Count +
                @($report.BroadMailboxAccess | Where-Object { $_.Risk -eq "MEDIUM" }).Count +
                @($report.ExternalDistributionListRisks | Where-Object { $_.Risk -eq "MEDIUM" }).Count
            )
            OverallRisk                   = if ($report.ExternalForwarding.Count -gt 0) { "HIGH" }
                                            elseif ($report.DLPAlerts.Count -gt 0 -or
                                                    $report.BroadMailboxAccess.Count -gt 0) { "MEDIUM" }
                                            else { "LOW" }
        }

        # Calculate hash for evidence integrity
        $jsonContent = $report | ConvertTo-Json -Depth 10
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($jsonContent))
            $report.metadata.contentHash = [BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
        }
        finally {
            $sha256.Dispose()
        }

        # Export report
        $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
        Write-AuditLog "Report exported to $OutputPath" "SUCCESS"
    }

    # Display summary
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                  Collection Summary                      ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "  External forwarding rules:     $($report.Summary.ExternalForwardingCount)" -ForegroundColor $(if ($report.Summary.ExternalForwardingCount -gt 0) { "Red" } else { "Green" })
    Write-Host "  DLP alerts (last $($config.retentionDays)d):        $($report.Summary.DLPAlertCount)" -ForegroundColor $(if ($report.Summary.DLPAlertCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  Inactive shared mailboxes:     $($report.Summary.InactiveSharedMailboxCount)" -ForegroundColor $(if ($report.Summary.InactiveSharedMailboxCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  DLs with external members:     $($report.Summary.ExternalDLMembershipCount)" -ForegroundColor $(if ($report.Summary.ExternalDLMembershipCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  Overall risk level:            $($report.Summary.OverallRisk)" -ForegroundColor $(switch ($report.Summary.OverallRisk) { "HIGH" { "Red" } "MEDIUM" { "Yellow" } default { "Green" } })
    Write-Host ""

    # Return structured summary for pipeline consumption
    [PSCustomObject]@{
        CorrelationId             = $script:CorrelationId
        CollectionDate            = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        ExternalForwardingCount   = $report.Summary.ExternalForwardingCount
        DLPAlertCount             = $report.Summary.DLPAlertCount
        InactiveSharedMailboxes   = $report.Summary.InactiveSharedMailboxCount
        ExternalDLMemberships     = $report.Summary.ExternalDLMembershipCount
        OverallRisk               = $report.Summary.OverallRisk
        OutputFile                = $OutputPath
    }
}
catch {
    Write-AuditLog "Exchange compliance collection failed: $($_.Exception.Message)" "ERROR"
    throw
}
finally {
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue } catch { }
}

#endregion
