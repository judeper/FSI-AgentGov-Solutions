#Requires -Version 7.0

# ExchangeOnlineManagement is bootstrapped at runtime instead of #Requires -Modules
# so the script can prompt to install or update the module when it isn't present.

<#
.SYNOPSIS
Creates or verifies the agent-intake Purview retention labels.

.DESCRIPTION
Creates the FSI-AgentIntake-7yr and FSI-AgentIntake-7yr-WORM retention labels by
using Security & Compliance PowerShell. The script is idempotent: existing labels
are reported and left unchanged. If ExchangeOnlineManagement 3.2.0 or later isn't
installed, the script offers to install it for the current user when running
interactively. Unattended runs should preinstall the module.

.PARAMETER LabelName
Name of the standard retention label.

.PARAMETER WormLabelName
Name of the immutable record-label variant.

.PARAMETER RetentionDays
Retention duration in days. The default is 2,555 days (7 years).

.PARAMETER AdminUpn
UPN of the account used with Connect-IPPSSession. If omitted, the script prompts
interactively.

.PARAMETER DryRun
Shows the New-ComplianceTag commands that would run for missing labels.

.EXAMPLE
pwsh .\setup_purview_retention_label.ps1 -AdminUpn recordsadmin@contoso.com

.EXAMPLE
pwsh .\setup_purview_retention_label.ps1 -AdminUpn recordsadmin@contoso.com -DryRun
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'PSScriptAnalyzer honors this rule at script or function scope; flagged compatibility parameters below include individual justifications.'
)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LabelName = 'FSI-AgentIntake-7yr',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WormLabelName = 'FSI-AgentIntake-7yr-WORM',

    [Parameter()]
    [ValidateRange(1, 36525)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [int]$RetentionDays = 2555,

    [Parameter()]
    [string]$AdminUpn,

    [Parameter()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:MinimumModuleVersion = [version]'3.2.0'

function Test-IsInteractiveSession {
    [CmdletBinding()]
    param()

    try {
        return [Environment]::UserInteractive -and $null -ne $Host.UI.RawUI
    }
    catch {
        return $false
    }
}

function Install-ExchangeOnlineManagementModule {
    [CmdletBinding()]
    param()

    $installedModule = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($installedModule -and $installedModule.Version -ge $script:MinimumModuleVersion) {
        return $installedModule
    }

    $reason = if ($installedModule) {
        "ExchangeOnlineManagement $($installedModule.Version) is older than the required $($script:MinimumModuleVersion)"
    }
    else {
        'ExchangeOnlineManagement is not installed'
    }

    if (-not (Test-IsInteractiveSession)) {
        throw "$reason. Install ExchangeOnlineManagement $($script:MinimumModuleVersion) or later before running unattended."
    }

    $reply = Read-Host "$reason. Install or update the module for the current user now? [Y/N]"
    if ($reply -notmatch '^(y|yes)$') {
        throw "ExchangeOnlineManagement $($script:MinimumModuleVersion) or later is required to manage retention labels."
    }

    Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber -MinimumVersion $script:MinimumModuleVersion
    return Get-Module -ListAvailable -Name ExchangeOnlineManagement |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

function Get-ResolvedAdminUpn {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CurrentValue
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue.Trim()
    }

    if (-not (Test-IsInteractiveSession)) {
        throw 'Provide -AdminUpn for unattended runs.'
    }

    $enteredUpn = Read-Host 'Records-management admin UPN'
    if ([string]::IsNullOrWhiteSpace($enteredUpn)) {
        throw 'Admin UPN is required.'
    }

    return $enteredUpn.Trim()
}

function New-ComplianceTagCommandText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$RetentionDuration,

        [Parameter(Mandatory)]
        [string]$Comment,

        [Parameter(Mandatory)]
        [bool]$IsRecordLabel
    )

    $commandText = @(
        'New-ComplianceTag'
        ('-Name "{0}"' -f $Name)
        '-RetentionAction Keep'
        ('-RetentionDuration {0}' -f $RetentionDuration)
        '-RetentionType CreationAgeInDays'
        ('-Comment "{0}"' -f $Comment.Replace('"', '\"'))
    )

    if ($IsRecordLabel) {
        $commandText += '-IsRecordLabel $true'
    }

    return ($commandText -join ' ')
}

function Add-RetentionLabelResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$IsRecordLabel,

        [Parameter(Mandatory)]
        [string]$Comment
    )

    $existingLabel = Get-ComplianceTag -Identity $Name -ErrorAction SilentlyContinue
    if ($null -ne $existingLabel) {
        Write-Host ("Retention label '{0}' is already present." -f $Name)
        return [pscustomobject]@{
            Name          = $Name
            Status        = 'AlreadyPresent'
            IsRecordLabel = [bool]$existingLabel.IsRecordLabel
            RetentionDays = $existingLabel.RetentionDuration
            Comment       = $existingLabel.Comment
        }
    }

    $commandText = New-ComplianceTagCommandText -Name $Name -RetentionDuration $RetentionDays -Comment $Comment -IsRecordLabel $IsRecordLabel
    if ($DryRun.IsPresent) {
        Write-Host ("[DRY RUN] {0}" -f $commandText)
        return [pscustomobject]@{
            Name          = $Name
            Status        = 'DryRunPending'
            IsRecordLabel = $IsRecordLabel
            RetentionDays = $RetentionDays
            Comment       = $Comment
        }
    }

    $parameters = @{
        Name              = $Name
        RetentionAction   = 'Keep'
        RetentionDuration = $RetentionDays
        RetentionType     = 'CreationAgeInDays'
        Comment           = $Comment
    }
    if ($IsRecordLabel) {
        $parameters.IsRecordLabel = $true
    }

    New-ComplianceTag @parameters | Out-Null
    Write-Host ("Created retention label '{0}'." -f $Name)

    return [pscustomobject]@{
        Name          = $Name
        Status        = 'Created'
        IsRecordLabel = $IsRecordLabel
        RetentionDays = $RetentionDays
        Comment       = $Comment
    }
}

$results = @()
$connected = $false

try {
    $module = Install-ExchangeOnlineManagementModule
    Import-Module ExchangeOnlineManagement -MinimumVersion $script:MinimumModuleVersion -ErrorAction Stop | Out-Null
    Write-Verbose ("Using ExchangeOnlineManagement {0}" -f $module.Version)

    $resolvedAdminUpn = Get-ResolvedAdminUpn -CurrentValue $AdminUpn

    Write-Host ("Connecting to Security & Compliance PowerShell as {0}..." -f $resolvedAdminUpn)
    # Use -DisableWAM to avoid silent/invisible webview2 popups (the WAM broker can
    # produce a popup that is invisible to remote-desktop / non-interactive operators
    # and causes Connect-IPPSSession to hang indefinitely). Default browser auth is
    # visible and reliable; MSAL token cache still applies on subsequent runs.
    Connect-IPPSSession -UserPrincipalName $resolvedAdminUpn -ShowBanner:$false -DisableWAM | Out-Null
    $connected = $true

    $results += Add-RetentionLabelResult -Name $LabelName -IsRecordLabel:$false -Comment 'FSI agent-intake decision records retained for 7 years.'
    $results += Add-RetentionLabelResult -Name $WormLabelName -IsRecordLabel:$true -Comment 'Immutable FSI agent-intake decision records retained for 7 years.'

    Write-Host ''
    Write-Host 'Retention label summary'
    $results | Format-Table Name, Status, IsRecordLabel, RetentionDays -AutoSize | Out-Host

    exit 0
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ($connected) {
        try {
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            Write-Verbose ("Exchange Online disconnect for retention label setup as {0} failed (non-fatal): {1}" -f $resolvedAdminUpn, $_.Exception.Message)
        }
    }
}
