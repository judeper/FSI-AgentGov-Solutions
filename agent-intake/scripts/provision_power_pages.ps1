#Requires -Version 7.0

<#
.SYNOPSIS
Validates and stages Power Pages provisioning for the agent-intake maker form.

.DESCRIPTION
Uses Microsoft Power Platform CLI (PAC CLI) to verify the target Dataverse environment, confirm the
Power Pages site exists, confirm the required Dataverse tables exist, and re-upload previously prepared
Power Pages site content when the agent-intake assets are already present.

PAC CLI references at time of writing:
- https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/pages
- https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/auth
- https://learn.microsoft.com/en-us/power-pages/configure/power-platform-cli

The current PAC CLI pages surface supports site discovery plus download/upload of website content.
It does not currently expose first-party commands to create a classic Power Pages site, create a classic
page, add a multistep form definition, configure table permissions, or bind Microsoft Graph pre-fill
logic directly. When those capabilities are missing, this script prints the manual fallback steps from
`docs/portal-configuration.md` and `docs/maker-form-progressive-disclosure.md`.

.PARAMETER EnvironmentUrl
Absolute Dataverse environment URL, for example `https://contoso.crm.dynamics.com`.

.PARAMETER SiteName
Display name of the target Power Pages site. Defaults to `agent-intake`.

.PARAMETER PageName
Page name / partial URL to validate. Defaults to `agent-intake`.

.PARAMETER DryRun
Shows the PAC CLI commands that would change state without changing local or remote content.

.EXAMPLE
.\provision_power_pages.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com

.EXAMPLE
.\provision_power_pages.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [ValidateNotNullOrEmpty()]
    [string]$SiteName = 'agent-intake',

    [ValidateNotNullOrEmpty()]
    [string]$PageName = 'agent-intake',

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pagesReference = 'https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/pages'
$authReference = 'https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/auth'
$powerPagesCliOverview = 'https://learn.microsoft.com/en-us/power-pages/configure/power-platform-cli'
$solutionRoot = Split-Path $PSScriptRoot -Parent
$portalDocPath = Join-Path $solutionRoot 'docs\portal-configuration.md'
$progressiveDocPath = Join-Path $solutionRoot 'docs\maker-form-progressive-disclosure.md'
$runtimeRoot = Join-Path $PSScriptRoot '.powerpages-runtime'
$requiredTables = @('fsi_intakerequest', 'fsi_intakedatasource', 'fsi_intakerisksignal')
$manualSteps = [System.Collections.Generic.List[string]]::new()
$summary = [System.Collections.Generic.List[object]]::new()

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Information ("`n== $Title ==") -InformationAction Continue
}

function Add-SummaryRow {
    param(
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Details
    )

    $summary.Add([pscustomobject]@{
            Component = $Component
            Status    = $Status
            Details   = $Details
        }) | Out-Null
}

function Add-ManualStep {
    param([Parameter(Mandatory)][string]$Text)
    $manualSteps.Add($Text) | Out-Null
}

function Invoke-PacCommand {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure,
        [switch]$ChangesState
    )

    $escapedArguments = foreach ($argument in $Arguments) {
        if ($argument -match '\s') {
            '"{0}"' -f $argument
        }
        else {
            $argument
        }
    }

    $commandText = 'pac ' + ($escapedArguments -join ' ')

    if ($DryRun -and $ChangesState) {
        Write-Information "[DRY-RUN] $commandText" -InformationAction Continue
        return [pscustomobject]@{
            Succeeded = $true
            Output    = ''
            Command   = $commandText
            ExitCode  = 0
            Skipped   = $true
        }
    }

    $output = & pac @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "PAC CLI command failed: $commandText`n$text"
    }

    return [pscustomobject]@{
        Succeeded = ($exitCode -eq 0)
        Output    = $text.Trim()
        Command   = $commandText
        ExitCode  = $exitCode
        Skipped   = $false
    }
}

function Get-SiteRecord {
    param(
        [Parameter(Mandatory)][string]$Output,
        [Parameter(Mandatory)][string]$Name
    )

    $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $candidateLines = $Output -split "\r?\n" | Where-Object { $_ -match [regex]::Escape($Name) }

    foreach ($line in $candidateLines) {
        $websiteId = [regex]::Match($line, $guidPattern).Value
        $modelVersion = if ($line -match '\bEnhanced\b') {
            'Enhanced'
        }
        elseif ($line -match '\bStandard\b') {
            'Standard'
        }
        else {
            $null
        }

        return [pscustomobject]@{
            Name         = $Name
            WebsiteId    = $websiteId
            ModelVersion = $modelVersion
            RawLine      = $line.Trim()
        }
    }

    return $null
}

function Get-SiteContentPath {
    param([Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    $websiteYaml = Get-ChildItem -LiteralPath $Root -Recurse -Filter 'website.yml' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $websiteYaml) {
        return $null
    }

    return $websiteYaml.Directory.FullName
}

function Test-SiteArtifact {
    param(
        [Parameter(Mandatory)][string]$SiteContentPath,
        [Parameter(Mandatory)][string]$PageName
    )

    if (-not (Test-Path -LiteralPath $SiteContentPath)) {
        return [pscustomobject]@{
            Exists  = $false
            Details = 'Downloaded site content was not found.'
        }
    }

    $webPagesPath = Join-Path $SiteContentPath 'web-pages'
    if (-not (Test-Path -LiteralPath $webPagesPath)) {
        return [pscustomobject]@{
            Exists  = $false
            Details = 'Downloaded site content does not contain a web-pages folder.'
        }
    }

    $pageFolder = Get-ChildItem -LiteralPath $webPagesPath -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq $PageName } |
        Select-Object -First 1

    $pageYaml = if ($pageFolder) {
        Get-ChildItem -LiteralPath $pageFolder.FullName -Filter '*.webpage.yml' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }

    if ($pageFolder -and $pageYaml) {
        return [pscustomobject]@{
            Exists  = $true
            Details = "Found $($pageYaml.FullName)"
        }
    }

    return [pscustomobject]@{
        Exists  = $false
        Details = "No *.webpage.yml asset found under web-pages\\$PageName."
    }
}

function Test-TablePermissionArtifacts {
    param(
        [Parameter(Mandatory)][string]$SiteContentPath,
        [Parameter(Mandatory)][string[]]$TableNames
    )

    $permissionFiles = @()
    if (Test-Path -LiteralPath $SiteContentPath) {
        $permissionFiles = Get-ChildItem -LiteralPath $SiteContentPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match 'table-permissions' }
    }

    foreach ($tableName in $TableNames) {
        $match = $false
        foreach ($file in $permissionFiles) {
            if (Select-String -Path $file.FullName -Pattern [regex]::Escape($tableName) -Quiet -ErrorAction SilentlyContinue) {
                $match = $true
                break
            }
        }

        [pscustomobject]@{
            Table  = $tableName
            Exists = $match
        }
    }
}

function Show-Summary {
    if ($summary.Count -gt 0) {
        Write-Section 'Provisioning summary'
        $summary | Format-Table -AutoSize
    }

    if ($manualSteps.Count -gt 0) {
        Write-Section 'Manual fallback steps'
        for ($index = 0; $index -lt $manualSteps.Count; $index++) {
            Write-Information ('{0}. {1}' -f ($index + 1), $manualSteps[$index]) -InformationAction Continue
        }
        Write-Information "See $portalDocPath and $progressiveDocPath for the full manual build sequence." -InformationAction Continue
    }
}

try {
    Write-Section 'Checking PAC CLI'
    $pacVersionResult = Invoke-PacCommand -Arguments @('--version') -AllowFailure
    $versionLine = ($pacVersionResult.Output -split "\r?\n" | Where-Object { $_ -match '^Version:' } | Select-Object -First 1)
    $pacVersion = if ($versionLine) {
        ($versionLine -replace '^Version:\s*', '').Trim()
    }
    elseif ($pacVersionResult.Output) {
        ($pacVersionResult.Output -split "\r?\n")[0].Trim()
    }
    else {
        'unknown'
    }
    Add-SummaryRow -Component 'PAC CLI' -Status 'Ready' -Details "Version $pacVersion"

    Write-Section 'Checking authentication'
    $authWho = Invoke-PacCommand -Arguments @('auth', 'who') -AllowFailure
    if (-not $authWho.Succeeded) {
        Add-SummaryRow -Component 'Authentication' -Status 'Manual step required' -Details "Run pac auth create --environment $EnvironmentUrl before rerunning the script."
        Add-ManualStep "Create or select a PAC auth profile for $EnvironmentUrl. Use 'pac auth create --environment `"$EnvironmentUrl`"' and complete Microsoft Entra ID sign-in. Reference: $authReference"
        Show-Summary
        return
    }
    Add-SummaryRow -Component 'Authentication' -Status 'Ready' -Details 'A PAC auth profile is active.'

    if ($DryRun) {
        Add-SummaryRow -Component 'Environment selection' -Status 'Planned' -Details "Would run pac env select --environment $EnvironmentUrl"
    }
    else {
        $envSelect = Invoke-PacCommand -Arguments @('env', 'select', '--environment', $EnvironmentUrl) -AllowFailure -ChangesState
        if ($envSelect.Succeeded) {
            Add-SummaryRow -Component 'Environment selection' -Status 'Ready' -Details $EnvironmentUrl
        }
        else {
            Add-SummaryRow -Component 'Environment selection' -Status 'Warning' -Details "The active PAC profile stayed on its current environment. Commands will still pass --environment $EnvironmentUrl."
        }
    }

    Write-Section 'Verifying Dataverse tables'
    $tableSearch = $requiredTables -join ','
    $tableList = Invoke-PacCommand -Arguments @('model', 'list-tables', '--environment', $EnvironmentUrl, '--search', $tableSearch)
    $missingTables = $requiredTables | Where-Object { $tableList.Output -notmatch [regex]::Escape($_) }
    if ($missingTables.Count -gt 0) {
        $missingList = $missingTables -join ', '
        Add-SummaryRow -Component 'Dataverse tables' -Status 'Blocked' -Details "Missing or not visible via PAC CLI: $missingList"
        throw "The target environment does not expose all required tables. Missing or not visible: $missingList"
    }
    Add-SummaryRow -Component 'Dataverse tables' -Status 'Ready' -Details ($requiredTables -join ', ')

    Write-Section 'Locating Power Pages site'
    $siteList = Invoke-PacCommand -Arguments @('pages', 'list', '--environment', $EnvironmentUrl, '-v')
    $site = Get-SiteRecord -Output $siteList.Output -Name $SiteName
    if (-not $site) {
        Add-SummaryRow -Component 'Power Pages site' -Status 'Manual step required' -Details "Site '$SiteName' was not found. PAC CLI can list sites but does not currently document a create-site command for classic sites."
        Add-ManualStep "Create a Power Pages site named '$SiteName' in the target environment, publish it once, and rerun this script. Reference: $pagesReference"
        Add-ManualStep "After the site exists, complete the classic page + multistep-form setup by following $portalDocPath and $progressiveDocPath."
        Show-Summary
        return
    }

    if (-not $site.WebsiteId) {
        Add-SummaryRow -Component 'Power Pages site' -Status 'Manual step required' -Details "Site '$SiteName' was found, but the website ID could not be parsed from the pac pages list output."
        Add-ManualStep "Run 'pac pages list --environment `"$EnvironmentUrl`" -v' manually, capture the site GUID for '$SiteName', and confirm the output shape before automating the download step."
        Show-Summary
        return
    }

    $modelVersion = if ($site.ModelVersion) { $site.ModelVersion } else { 'Standard' }
    Add-SummaryRow -Component 'Power Pages site' -Status 'Ready' -Details "$($site.Name) ($($site.WebsiteId)) / model $modelVersion"

    $siteContentPath = $null
    if ($DryRun) {
        Add-SummaryRow -Component 'PAC download' -Status 'Planned' -Details "Would run pac pages download --environment $EnvironmentUrl --path $runtimeRoot --webSiteId $($site.WebsiteId) --modelVersion $modelVersion --overwrite"
        $siteContentPath = Get-SiteContentPath -Root $runtimeRoot
        if ($siteContentPath) {
            Add-SummaryRow -Component 'Existing site content cache' -Status 'Ready' -Details $siteContentPath
        }
        else {
            Add-SummaryRow -Component 'Existing site content cache' -Status 'Not inspected' -Details 'No cached website.yml was found under the runtime folder during dry-run mode.'
        }
    }
    else {
        Write-Section 'Downloading site content'
        New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
        $null = Invoke-PacCommand -Arguments @('pages', 'download', '--environment', $EnvironmentUrl, '--path', $runtimeRoot, '--webSiteId', $site.WebsiteId, '--overwrite', '--modelVersion', $modelVersion) -ChangesState
        $siteContentPath = Get-SiteContentPath -Root $runtimeRoot
        if (-not $siteContentPath) {
            Add-SummaryRow -Component 'Downloaded site content' -Status 'Manual step required' -Details 'PAC CLI download completed, but the local site folder could not be resolved automatically.'
            Add-ManualStep "Inspect $runtimeRoot, locate the folder that contains website.yml, and confirm the agent-intake page assets exist before using pac pages upload."
            Show-Summary
            return
        }
        Add-SummaryRow -Component 'Downloaded site content' -Status 'Ready' -Details $siteContentPath
    }

    if ($siteContentPath) {
        Write-Section 'Checking page asset'
        $pageAsset = Test-SiteArtifact -SiteContentPath $siteContentPath -PageName $PageName
        if ($pageAsset.Exists) {
            Add-SummaryRow -Component 'Page asset' -Status 'Ready' -Details $pageAsset.Details
        }
        else {
            Add-SummaryRow -Component 'Page asset' -Status 'Manual step required' -Details $pageAsset.Details
            Add-ManualStep "Create the '$PageName' page and bind it to the agent-intake multistep form in Power Pages design studio or Portal Management app. PAC CLI does not currently document a create-page or create-multistep-form command for classic sites."
        }

        Write-Section 'Checking table permission assets'
        $permissionResults = @(Test-TablePermissionArtifacts -SiteContentPath $siteContentPath -TableNames $requiredTables)
        $missingPermissionTables = $permissionResults | Where-Object { -not $_.Exists } | Select-Object -ExpandProperty Table
        if ($missingPermissionTables) {
            Add-SummaryRow -Component 'Table permission assets' -Status 'Manual step required' -Details "No table-permission artifact was found for: $($missingPermissionTables -join ', ')"
            Add-ManualStep "Configure table permissions for fsi_intakerequest (Create, Read own, Update own while Draft), fsi_intakedatasource (Create, Read own, Update own while Draft), and fsi_intakerisksignal (Read own) as documented in $portalDocPath."
        }
        else {
            Add-SummaryRow -Component 'Table permission assets' -Status 'Ready' -Details ($requiredTables -join ', ')
        }

        if (-not $DryRun -and -not $missingPermissionTables -and $pageAsset.Exists) {
            Write-Section 'Re-uploading site content'
            $null = Invoke-PacCommand -Arguments @('pages', 'upload', '--environment', $EnvironmentUrl, '--path', $siteContentPath, '--modelVersion', $modelVersion) -ChangesState
            Add-SummaryRow -Component 'PAC upload' -Status 'Completed' -Details "Re-uploaded site content from $siteContentPath"
        }
        elseif ($DryRun) {
            Add-SummaryRow -Component 'PAC upload' -Status 'Planned' -Details "Would run pac pages upload --environment $EnvironmentUrl --path <site-content-path> --modelVersion $modelVersion once the page and table-permission assets are present."
        }
        else {
            Add-SummaryRow -Component 'PAC upload' -Status 'Skipped' -Details 'Skipped because the page asset or required table-permission assets are still missing.'
        }
    }

    Write-Section 'Graph pre-fill / classifier integration'
    Add-SummaryRow -Component 'Graph pre-fill' -Status 'Manual step required' -Details 'PAC CLI has no first-party command to bind Microsoft Graph /me or /me/manager pre-fill logic to a classic Power Pages form.'
    Add-ManualStep "Configure Microsoft Graph pre-fill for fsi_makerupn, fsi_makerdisplayname, fsi_makerdepartment, fsi_makerjobtitle, fsi_makercountry, and fsi_sponsorupn by following the integration notes in $portalDocPath and $progressiveDocPath."
    Add-ManualStep 'Add the pre-submit classifier flow so Step 1 writes fsi_pathused, fsi_decisionpath, and fsi_standardfullquestionsjson before the multistep form evaluates the Standard and Full gates.'

    Show-Summary
}
catch {
    Add-SummaryRow -Component 'Script result' -Status 'Failed' -Details $_.Exception.Message
    Show-Summary
    throw
}
