#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0' }, @{ ModuleName = 'powershell-yaml'; ModuleVersion = '0.4.0' }

<#
.SYNOPSIS
    End-to-end orchestrator for the FSI agent-intake solution.

.DESCRIPTION
    Idempotently deploys or tears down the agent-intake solution in a Power Platform
    environment. Covers 8 stages: schema, solution containers, reviewer-app provisioning,
    documented Power Automate flows, identity / security roles, Purview retention-label
    hydration, policy-table hydration, optional seed + smoke verification. Safe to re-run
    against the same environment; each stage detects existing state and is additive.

.PARAMETER EnvironmentUrl
    The Power Platform environment URL (for example, https://<your-env>.crm.dynamics.com).

.PARAMETER PolicyTablesPath
    Path to policy-lookup-tables.yaml. Defaults to ../templates/policy-lookup-tables.yaml.

.PARAMETER Teardown
    Destructively removes the agent-intake footprint from the environment.

.PARAMETER SeedTestData
    After deploy, runs seed-test-data.ps1.

.PARAMETER SkipSmoke
    Skip the smoke test stages.

.PARAMETER SkipPurviewLabel
    Skip the Stage 3 Purview retention-label creation step (for unattended lab runs where the
    retention labels already exist; avoids the interactive Connect-IPPSSession path).

.PARAMETER DryRun
    Logs what would be done without making changes.

.PARAMETER LogPath
    File path for the structured log. Default: ./agent-intake-deploy-<UTC timestamp>.log

.PARAMETER AuthMode
    AzCli (default — delegated; az login) | ManagedIdentity | ServicePrincipal (legacy: dev-only).
    For production deployments, prefer ManagedIdentity. Token-acquisition functions also accept
    pre-acquired tokens via env vars (managed-identity-friendly without changing AuthMode):
        DATAVERSE_ACCESS_TOKEN    — for Dataverse Web API calls
        BAP_ACCESS_TOKEN          — for https://api.bap.microsoft.com
        POWERPLATFORM_API_TOKEN   — for https://api.powerplatform.com (billing)

.PARAMETER BillingPolicyId
    GUID of a Power Platform Pay-as-you-go billing policy to attach the environment to so
    Copilot/AI Builder credits draw from the customer's Azure subscription. When supplied
    together with EnvironmentId, Stage 0 validates and attaches the policy. Discover via
    GET https://api.powerplatform.com/licensing/billingPolicies?api-version=2022-03-01-preview.

.PARAMETER EnvironmentId
    GUID of the Power Platform environment (the underlying env, not the org). Required when
    BillingPolicyId is supplied. Used by Stage 0 BAP / billing pre-flight checks.

.PARAMETER AllowedEnvironmentType
    Comma-separated list of environment SKUs allowed for billing-policy attachment.
    Default 'Sandbox,Production' fails fast when the env is Trial/Developer/Teams (which
    cannot be attached to a billing policy). Set 'Any' to bypass the SKU guard for testing.

.EXAMPLE
    pwsh ./deploy.ps1 -EnvironmentUrl https://<your-env>.crm.dynamics.com

.EXAMPLE
    pwsh ./deploy.ps1 -EnvironmentUrl https://<your-env>.crm.dynamics.com -SeedTestData

.EXAMPLE
    pwsh ./deploy.ps1 -EnvironmentUrl https://<your-env>.crm.dynamics.com -Teardown

.EXAMPLE
    # Attach a billing policy in the same run (typical lab cycle)
    pwsh ./deploy.ps1 `
        -EnvironmentUrl  https://<your-env>.crm.dynamics.com `
        -EnvironmentId   00000000-0000-0000-0000-000000000000 `
        -BillingPolicyId 00000000-0000-0000-0000-000000000000
#>
[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'PSScriptAnalyzer honors this rule at script or function scope; flagged compatibility parameters below include individual justifications.'
)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [ValidateNotNullOrEmpty()]
    [string]$PolicyTablesPath = "$PSScriptRoot/../templates/policy-lookup-tables.yaml",

    [switch]$Teardown,

    [switch]$SeedTestData,

    [switch]$SkipSmoke,

    [switch]$SkipPurviewLabel,

    [switch]$DryRun,

    [string]$LogPath,

    [ValidateSet('AzCli', 'ManagedIdentity', 'ServicePrincipal')]
    [string]$AuthMode = 'AzCli',

    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [string]$BillingPolicyId,

    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [string]$EnvironmentId,

    [ValidateSet('Sandbox', 'Production', 'Sandbox,Production', 'Any')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [string]$AllowedEnvironmentType = 'Sandbox,Production'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$script:TargetEnvironmentUrl = $EnvironmentUrl
$script:IsDryRun = [bool]$DryRun
$script:SelectedAuthMode = $AuthMode

$script:SolutionRoot = Split-Path -Path $PSScriptRoot -Parent
$script:RuntimeRoot = Join-Path -Path $PSScriptRoot -ChildPath '.deploy-runtime'
$script:ReviewerSpecPath = Join-Path -Path $script:SolutionRoot -ChildPath 'templates\reviewer-app-spec.json'
$script:PolicyTablesPath = [System.IO.Path]::GetFullPath($PolicyTablesPath)
$script:StageSummary = [System.Collections.Generic.List[object]]::new()
$script:TeardownSummary = [System.Collections.Generic.List[object]]::new()
$script:EnvironmentMetadata = $null
$script:DataverseToken = $null
$script:BapAccessToken = $null
$script:PowerPlatformApiAccessToken = $null
$script:StructuredLogPath = if ([string]::IsNullOrWhiteSpace($LogPath)) {
    Join-Path -Path $PSScriptRoot -ChildPath ('agent-intake-deploy-{0}.log' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')))
}
else {
    [System.IO.Path]::GetFullPath($LogPath)
}
$script:EntityMap = @{
    fsi_intakerequest         = @{ EntitySetName = 'fsi_intakerequests'; PrimaryIdAttribute = 'fsi_intakerequestid' }
    fsi_intakedatasource      = @{ EntitySetName = 'fsi_intakedatasources'; PrimaryIdAttribute = 'fsi_intakedatasourceid' }
    fsi_intakerisksignal      = @{ EntitySetName = 'fsi_intakerisksignals'; PrimaryIdAttribute = 'fsi_intakerisksignalid' }
    fsi_intakereview          = @{ EntitySetName = 'fsi_intakereviews'; PrimaryIdAttribute = 'fsi_intakereviewid' }
    fsi_intakeapproval        = @{ EntitySetName = 'fsi_intakeapprovals'; PrimaryIdAttribute = 'fsi_intakeapprovalid' }
    fsi_intakedecisionlog     = @{ EntitySetName = 'fsi_intakedecisionlogs'; PrimaryIdAttribute = 'fsi_intakedecisionlogid' }
    fsi_intakesponsorship     = @{ EntitySetName = 'fsi_intakesponsorships'; PrimaryIdAttribute = 'fsi_intakesponsorshipid' }
    fsi_intakeauditevent      = @{ EntitySetName = 'fsi_intakeauditevents'; PrimaryIdAttribute = 'fsi_intakeauditeventid' }
    fsi_intakeretentionrecord = @{ EntitySetName = 'fsi_intakeretentionrecords'; PrimaryIdAttribute = 'fsi_intakeretentionrecordid' }
}
$script:TableNameList = @(
    'fsi_intakerequest',
    'fsi_intakedatasource',
    'fsi_intakerisksignal',
    'fsi_intakereview',
    'fsi_intakeapproval',
    'fsi_intakedecisionlog',
    'fsi_intakesponsorship',
    'fsi_intakeauditevent',
    'fsi_intakeretentionrecord'
)
$script:OptionSetNameList = @(
    'fsi_acv_zone',
    'fsi_intake_pathused',
    'fsi_intake_status',
    'fsi_intake_routingtopology',
    'fsi_intake_risktier',
    'fsi_intake_agenttype',
    'fsi_intake_dataclassification',
    'fsi_intake_reviewerrole',
    'fsi_intake_reviewdecision',
    'fsi_intake_mrmhandoffstatus',
    'fsi_intake_decisionoutcome'
)
$script:KeyColumnMap = @{
    fsi_intakerequest = @('fsi_requestid', 'fsi_agentdisplayname', 'fsi_pathused', 'fsi_risktier', 'fsi_zone', 'fsi_status', 'fsi_policyversionapplied')
    fsi_intakedatasource = @('fsi_requestid', 'fsi_datasourcename', 'fsi_dataclassification')
    fsi_intakerisksignal = @('fsi_requestid', 'fsi_triggercode', 'fsi_triggeranswer')
    fsi_intakereview = @('fsi_requestid', 'fsi_reviewerrole', 'fsi_reviewoutcome')
    fsi_intakeapproval = @('fsi_requestid', 'fsi_approverrole', 'fsi_decisionoutcome')
    fsi_intakedecisionlog = @('fsi_requestid', 'fsi_decisionoutcome', 'fsi_decisionpackhash')
    fsi_intakesponsorship = @('fsi_requestid', 'fsi_sponsorupn', 'fsi_attestationmethod')
    fsi_intakeauditevent = @('fsi_requestid', 'fsi_eventtype', 'fsi_eventon')
    fsi_intakeretentionrecord = @('fsi_requestid', 'fsi_labelname', 'fsi_stampedon')
}
$script:EnvVarSchemaNameList = @(
    'fsi_intake_powerplatformenvironmenturl',
    'fsi_intake_makerportalurl',
    'fsi_intake_reviewerappurl',
    'fsi_intake_mrmtargetenv',
    'fsi_intake_driftdetectorenv',
    'fsi_intake_retentionlabelid',
    'fsi_intake_sponsorbackupgroup'
)
$script:ConnectionReferenceNameList = @(
    'fsi_cr_dataverse_agentintake',
    'fsi_cr_teams_agentintake',
    'fsi_cr_office365_agentintake',
    'fsi_cr_http_agentintake'
)
$script:ExitCodeMap = @{
    Preflight = 10
    Schema = 20
    Shell = 30
    Identity = 40
    Maker = 50
    Reviewer = 60
    Policy = 70
    Smoke = 80
    Seed = 90
    Teardown = 100
}

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Information "[deploy] $Message" -InformationAction Continue
}

function Write-WarnMessage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Warning "[deploy] $Message"
}

function Write-ManualMessage {
    param([Parameter(Mandatory)][string]$Message)
    Write-WarnMessage "MANUAL STEP REQUIRED: $Message"
}

function Add-StageSummaryRecord {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][long]$DurationMs,
        [Parameter()][string]$Detail
    )

    $script:StageSummary.Add([pscustomobject]@{
            Stage = $Stage
            Status = $Status
            DurationMs = $DurationMs
            Detail = $Detail
        }) | Out-Null
}

function Add-TeardownSummaryRecord {
    param(
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )

    $script:TeardownSummary.Add([pscustomobject]@{
            Component = $Component
            Status = $Status
            Detail = $Detail
        }) | Out-Null
}

function Write-StructuredStageLog {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][datetime]$StartedAt,
        [Parameter(Mandatory)][datetime]$CompletedAt,
        [Parameter(Mandatory)][long]$DurationMs,
        [string]$Detail,
        [string]$ErrorText
    )

    $entry = [ordered]@{
        stage = $Stage
        status = $Status
        started_at = $StartedAt.ToUniversalTime().ToString('o')
        completed_at = $CompletedAt.ToUniversalTime().ToString('o')
        duration_ms = $DurationMs
        detail = $Detail
        errors = if ([string]::IsNullOrWhiteSpace($ErrorText)) { @() } else { @($ErrorText) }
    }

    Add-Content -LiteralPath $script:StructuredLogPath -Value (($entry | ConvertTo-Json -Depth 8 -Compress) + [Environment]::NewLine)
}

function Invoke-StageAction {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][int]$FailureCode,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $startedAt = Get-Date
    try {
        $result = & $Action
        $completedAt = Get-Date
        $durationMs = [long][Math]::Round(($completedAt - $startedAt).TotalMilliseconds)
        $status = if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'Status') { [string]$result.Status } else { 'Success' }
        $detail = if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'Detail') { [string]$result.Detail } else { '' }
        Add-StageSummaryRecord -Stage $Stage -Status $status -DurationMs $durationMs -Detail $detail
        Write-StructuredStageLog -Stage $Stage -Status $status -StartedAt $startedAt -CompletedAt $completedAt -DurationMs $durationMs -Detail $detail
        return $result
    }
    catch {
        $completedAt = Get-Date
        $durationMs = [long][Math]::Round(($completedAt - $startedAt).TotalMilliseconds)
        $errorText = $_.Exception.Message
        Add-StageSummaryRecord -Stage $Stage -Status 'Failed' -DurationMs $durationMs -Detail $errorText
        Write-StructuredStageLog -Stage $Stage -Status 'Failed' -StartedAt $startedAt -CompletedAt $completedAt -DurationMs $durationMs -ErrorText $errorText
        Write-Error "Stage failed [$Stage]: $errorText"
        exit $FailureCode
    }
}

function Get-CommandVersionText {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }

    $output = & $command.Source @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return (($output | Select-Object -First 1) -as [string]).Trim()
}

function Get-PythonCommand {
    foreach ($candidate in @('python', 'py')) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Name
        }
    }

    throw 'Python 3.10 or later is required.'
}

function Test-PythonVersion {
    $python = Get-PythonCommand
    $output = & $python --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'Python is installed but did not return a version.'
    }

    $versionText = ($output -join ' ')
    if ($versionText -notmatch '(\d+)\.(\d+)\.(\d+)') {
        throw "Could not parse Python version from '$versionText'."
    }

    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 10)) {
        throw "Python 3.10 or later is required. Found $versionText."
    }

    return $versionText.Trim()
}

function Test-PythonPackage {
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$FriendlyName
    )

    $python = Get-PythonCommand
    $code = "import $ModuleName"
    & $python -c $code 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Python package '$FriendlyName' is required. Install it before running deploy.ps1."
    }
}

function Test-ModuleVersion {
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][version]$MinimumVersion,
        [switch]$Optional
    )

    $module = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $module) {
        if ($Optional) {
            return [pscustomobject]@{ Present = $false; Version = $null }
        }

        throw "PowerShell module '$ModuleName' is required."
    }

    if ($module.Version -lt $MinimumVersion) {
        throw "PowerShell module '$ModuleName' version $MinimumVersion or later is required. Found $($module.Version)."
    }

    return [pscustomobject]@{ Present = $true; Version = $module.Version }
}

function Test-AzCliContext {
    $az = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -eq $az) {
        return $false
    }

    & $az.Source account show --only-show-errors 1>$null 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Get-RequiredEnvironmentValue {
    param([Parameter(Mandatory)][string]$Name)

    $value = [System.Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Environment variable '$Name' is required for AuthMode ServicePrincipal."
    }

    return $value.Trim()
}

function Initialize-AzCliContext {
    $az = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -eq $az) {
        throw 'Azure CLI (az) is required.'
    }

    if ($DryRun) {
        return 'Dry-run: Azure CLI authentication not changed.'
    }

    if (Test-AzCliContext) {
        return 'Azure CLI context already authenticated.'
    }

    switch ($AuthMode) {
        'ManagedIdentity' {
            $arguments = @('login', '--identity')
            if (-not [string]::IsNullOrWhiteSpace($env:AZURE_CLIENT_ID)) {
                $arguments += @('--username', $env:AZURE_CLIENT_ID)
            }
            $output = & $az.Source @arguments 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Managed identity sign-in failed: $($output -join ' ')"
            }
            return 'Azure CLI connected with managed identity.'
        }
        'ServicePrincipal' {
            # legacy: dev-only - replace with managed identity in production
            $tenantId = Get-RequiredEnvironmentValue -Name 'AZURE_TENANT_ID'
            $clientId = Get-RequiredEnvironmentValue -Name 'AZURE_CLIENT_ID'
            $clientSecret = Get-RequiredEnvironmentValue -Name 'AZURE_CLIENT_SECRET'
            $arguments = @('login', '--service-principal', '--username', $clientId, '--password', $clientSecret, '--tenant', $tenantId, '--allow-no-subscriptions')
            $output = & $az.Source @arguments 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Service principal sign-in failed: $($output -join ' ')"
            }
            return 'Azure CLI connected with legacy service principal auth.'
        }
        default {
            $output = & $az.Source login --use-device-code 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Azure CLI delegated sign-in failed: $($output -join ' ')"
            }
            return 'Azure CLI delegated sign-in completed.'
        }
    }
}

function Test-PacContext {
    $pac = Get-Command -Name 'pac' -ErrorAction SilentlyContinue
    if ($null -eq $pac) {
        return $false
    }

    & $pac.Source auth who 1>$null 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Initialize-PacContext {
    $pac = Get-Command -Name 'pac' -ErrorAction SilentlyContinue
    if ($null -eq $pac) {
        throw 'Power Platform CLI (pac) is required.'
    }

    if ($DryRun) {
        return 'Dry-run: PAC authentication not changed.'
    }

    if (Test-PacContext) {
        return 'PAC auth profile already active.'
    }

    switch ($AuthMode) {
        'ManagedIdentity' {
            $arguments = @('auth', 'create', '--managedIdentity', '--environment', $EnvironmentUrl)
        }
        'ServicePrincipal' {
            $tenantId = Get-RequiredEnvironmentValue -Name 'AZURE_TENANT_ID'
            $clientId = Get-RequiredEnvironmentValue -Name 'AZURE_CLIENT_ID'
            $clientSecret = Get-RequiredEnvironmentValue -Name 'AZURE_CLIENT_SECRET'
            $arguments = @('auth', 'create', '--applicationId', $clientId, '--clientSecret', $clientSecret, '--tenant', $tenantId, '--environment', $EnvironmentUrl)
        }
        default {
            $arguments = @('auth', 'create', '--deviceCode', '--environment', $EnvironmentUrl)
        }
    }

    $output = & $pac.Source @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "PAC authentication failed: $($output -join ' ')"
    }

    return 'PAC auth profile created.'
}

function Select-PacEnvironment {
    $pac = Get-Command -Name 'pac' -ErrorAction SilentlyContinue
    if ($null -eq $pac) {
        throw 'Power Platform CLI (pac) is required.'
    }

    if ($DryRun) {
        return 'Dry-run: PAC environment selection not changed.'
    }

    $output = & $pac.Source env select --environment $EnvironmentUrl 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "PAC environment selection failed: $($output -join ' ')"
    }

    return 'PAC environment selected.'
}

function Get-PythonTokenSource {
    if ($AuthMode -eq 'ManagedIdentity') {
        return 'mi'
    }

    return 'cli'
}

function Get-DataverseToken {
    param(
        [switch]$Force
    )

    if ($DryRun) {
        return 'dry-run-token'
    }

    if ($Force) {
        $script:DataverseToken = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($script:DataverseToken)) {
        return $script:DataverseToken
    }

    if (-not $Force) {
        $envToken = $env:DATAVERSE_ACCESS_TOKEN
        if (-not [string]::IsNullOrWhiteSpace($envToken)) {
            $script:DataverseToken = $envToken.Trim()
            return $script:DataverseToken
        }
    }

    $az = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -eq $az) {
        throw 'Azure CLI (az) is required to acquire a Dataverse access token.'
    }

    $token = & $az.Source account get-access-token --resource $EnvironmentUrl --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw 'Could not acquire a Dataverse access token from Azure CLI.'
    }

    $script:DataverseToken = $token.Trim()
    return $script:DataverseToken
}

function Get-DataverseHeader {
    return @{
        Authorization = "Bearer $(Get-DataverseToken)"
        Accept = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
    }
}

function Get-AzureAccessTokenForResource {
    <#
    .SYNOPSIS
        Acquires a bearer token for an Azure / Power Platform resource.

    .DESCRIPTION
        Resolution order (managed-identity-first):
          1. If a resource-specific env var is set, return that token. Production callers
             SHOULD inject a token acquired from managed identity, workload identity
             federation, or another production-grade credential source via env var.
          2. Fall back to delegated `az` CLI. This is the development path and is
             marked legacy below.

        Recognised env vars by resource:
          - https://api.bap.microsoft.com/   → BAP_ACCESS_TOKEN
          - https://api.powerplatform.com/   → POWERPLATFORM_API_TOKEN
    #>
    param([Parameter(Mandatory)][string]$Resource)

    if ($DryRun) {
        return 'dry-run-token'
    }

    $envVarName = switch -Regex ($Resource) {
        '^https://api\.bap\.microsoft\.com/?$'  { 'BAP_ACCESS_TOKEN';        break }
        '^https://api\.powerplatform\.com/?$'   { 'POWERPLATFORM_API_TOKEN'; break }
        default                                 { $null }
    }
    if ($envVarName) {
        $envToken = [Environment]::GetEnvironmentVariable($envVarName)
        if (-not [string]::IsNullOrWhiteSpace($envToken)) {
            return $envToken.Trim()
        }
    }

    # legacy: dev-only — replace with managed identity in production
    $az = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -eq $az) {
        $hint = if ($envVarName) {
            "For production, set env var $envVarName with a managed-identity or WIF-acquired token."
        } else {
            'Set the appropriate access-token env var to bypass az CLI in production.'
        }
        throw "Azure CLI (az) is required to acquire access tokens. $hint"
    }

    $token = & $az.Source account get-access-token --resource $Resource --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Could not acquire access token for resource '$Resource' from Azure CLI."
    }

    return $token.Trim()
}

function Get-BapAccessToken {
    if (-not [string]::IsNullOrWhiteSpace($script:BapAccessToken)) {
        return $script:BapAccessToken
    }
    $script:BapAccessToken = Get-AzureAccessTokenForResource -Resource 'https://api.bap.microsoft.com/'
    return $script:BapAccessToken
}

function Get-PowerPlatformApiAccessToken {
    if (-not [string]::IsNullOrWhiteSpace($script:PowerPlatformApiAccessToken)) {
        return $script:PowerPlatformApiAccessToken
    }
    $script:PowerPlatformApiAccessToken = Get-AzureAccessTokenForResource -Resource 'https://api.powerplatform.com/'
    return $script:PowerPlatformApiAccessToken
}

function Get-EnvironmentSkuFromBap {
    <#
    .SYNOPSIS
        Returns the environmentSku (Trial / Sandbox / Production / Developer / Teams / Default)
        for the deploy-target environment from the BAP admin API.
    #>
    param([Parameter(Mandatory)][string]$EnvironmentId)

    if ($DryRun) {
        return 'Sandbox'
    }

    $token = Get-BapAccessToken
    $uri = 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/{0}/?api-version=2021-04-01' -f $EnvironmentId
    $response = Invoke-WebRequest -Uri $uri -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' } -UseBasicParsing -SkipHttpErrorCheck
    if ($response.StatusCode -ge 400) {
        $body = if ($response.Content.Length -gt 500) { $response.Content.Substring(0,500) + '...' } else { $response.Content }
        throw "Could not read environment metadata from BAP for $EnvironmentId (HTTP $($response.StatusCode) $body)."
    }
    $body = $response.Content | ConvertFrom-Json
    if ($null -eq $body -or $null -eq $body.PSObject.Properties['properties']) {
        throw "BAP response for $EnvironmentId did not include 'properties'."
    }
    $sku = $body.properties.PSObject.Properties['environmentSku']
    if ($null -eq $sku) {
        throw "BAP response for $EnvironmentId did not include 'environmentSku'."
    }
    return [string]$sku.Value
}

function Test-BillingPolicyAttachment {
    <#
    .SYNOPSIS
        Returns $true when EnvironmentId is already attached to BillingPolicyId.
    #>
    param(
        [Parameter(Mandatory)][string]$BillingPolicyId,
        [Parameter(Mandatory)][string]$EnvironmentId
    )

    if ($DryRun) {
        return $false
    }

    $token = Get-PowerPlatformApiAccessToken
    $uri = 'https://api.powerplatform.com/licensing/billingPolicies/{0}/environments?api-version=2022-03-01-preview' -f $BillingPolicyId
    $response = Invoke-WebRequest -Uri $uri -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' } -UseBasicParsing -SkipHttpErrorCheck
    if ($response.StatusCode -ge 400) {
        $body = if ($response.Content.Length -gt 500) { $response.Content.Substring(0,500) + '...' } else { $response.Content }
        throw "Could not list billing-policy environments for $BillingPolicyId (HTTP $($response.StatusCode) $body)."
    }
    $payload = $response.Content | ConvertFrom-Json
    if ($null -eq $payload -or $null -eq $payload.PSObject.Properties['value'] -or $null -eq $payload.value) {
        return $false
    }
    foreach ($item in $payload.value) {
        if ($null -eq $item -or $null -eq $item.PSObject.Properties['environmentId']) { continue }
        if ([string]::Equals([string]$item.environmentId, $EnvironmentId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Add-BillingPolicyAttachment {
    <#
    .SYNOPSIS
        Attaches EnvironmentId to BillingPolicyId via api.powerplatform.com.
        Idempotent: skips when already attached.
    #>
    param(
        [Parameter(Mandatory)][string]$BillingPolicyId,
        [Parameter(Mandatory)][string]$EnvironmentId
    )

    if ($DryRun) {
        return 'PlannedAttach'
    }

    if (Test-BillingPolicyAttachment -BillingPolicyId $BillingPolicyId -EnvironmentId $EnvironmentId) {
        return 'AlreadyAttached'
    }

    $token = Get-PowerPlatformApiAccessToken
    $uri = 'https://api.powerplatform.com/licensing/billingPolicies/{0}/environments/add?api-version=2022-03-01-preview' -f $BillingPolicyId
    $body = @{ environmentIds = @($EnvironmentId) } | ConvertTo-Json -Compress
    $response = Invoke-WebRequest -Uri $uri -Method Post -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'Content-Type' = 'application/json' } -Body $body -UseBasicParsing -SkipHttpErrorCheck
    if ($response.StatusCode -ge 400) {
        $bodyText = if ($response.Content.Length -gt 500) { $response.Content.Substring(0,500) + '...' } else { $response.Content }
        throw "Could not attach environment $EnvironmentId to billing policy $BillingPolicyId (HTTP $($response.StatusCode) $bodyText)."
    }
    return 'Attached'
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$RelativeUri,

        [object]$Body,

        [switch]$AllowNotFound
    )

    $uri = '{0}/api/data/v9.2/{1}' -f $EnvironmentUrl.TrimEnd('/'), $RelativeUri.TrimStart('/')
    if ($DryRun) {
        Write-Info "[DRY RUN] $Method $uri"
        if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
            Write-Info (ConvertTo-Json -InputObject $Body -Depth 20 -Compress)
        }

        return [pscustomobject]@{ StatusCode = 200; Body = $null; Headers = @{} }
    }

    $headers = Get-DataverseHeader
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $headers['Content-Type'] = 'application/json; charset=utf-8'
    }

    $bodyJson = $null
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $bodyJson = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
    }

    $response = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -Body $bodyJson -UseBasicParsing -SkipHttpErrorCheck
    if ($response.StatusCode -eq 401) {
        Write-Info "Dataverse token rejected (HTTP 401); refreshing via Azure CLI and retrying $Method $RelativeUri."
        try {
            Get-DataverseToken -Force | Out-Null
            $headers = Get-DataverseHeader
            if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
                $headers['Content-Type'] = 'application/json; charset=utf-8'
            }
            $response = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -Body $bodyJson -UseBasicParsing -SkipHttpErrorCheck
        }
        catch {
            Write-WarnMessage "Dataverse token refresh failed: $_"
        }
    }
    if ($AllowNotFound -and $response.StatusCode -eq 404) {
        return $null
    }

    if ($response.StatusCode -ge 400) {
        throw "Dataverse request failed ($Method $RelativeUri): HTTP $($response.StatusCode) $($response.Content)"
    }

    $payload = $null
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
        try {
            $payload = $response.Content | ConvertFrom-Json -AsHashtable
        }
        catch {
            $payload = $response.Content
        }
    }

    return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $payload; Headers = $response.Headers }
}

function ConvertTo-ODataStringLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'{0}'" -f $Value.Replace("'", "''")
}

function Get-EnvironmentIdByUrl {
    <#
    .SYNOPSIS
        Looks up the environment ID via the BAP admin API by matching the
        deploy-target Dataverse URL against properties.linkedEnvironmentMetadata.instanceUrl.
        Used only when the caller did not supply -EnvironmentId.
    #>
    param([Parameter(Mandatory)][string]$Url)

    if ($DryRun) {
        return '00000000-0000-4000-8000-000000000000'
    }

    $token = Get-BapAccessToken
    $uri = 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2021-04-01&$expand=properties&$top=999'
    $response = Invoke-WebRequest -Uri $uri -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' } -UseBasicParsing -SkipHttpErrorCheck
    if ($response.StatusCode -ge 400) {
        throw "Could not list environments from BAP (HTTP $($response.StatusCode))."
    }
    $payload = $response.Content | ConvertFrom-Json
    if ($null -eq $payload -or $null -eq $payload.PSObject.Properties['value']) {
        throw "Unexpected BAP response shape when listing environments for $Url."
    }
    $needle = $Url.TrimEnd('/')
    foreach ($envItem in $payload.value) {
        if ($null -eq $envItem -or $null -eq $envItem.PSObject.Properties['properties']) { continue }
        $linked = $envItem.properties.PSObject.Properties['linkedEnvironmentMetadata']
        if ($null -eq $linked -or $null -eq $linked.Value) { continue }
        $instance = $linked.Value.PSObject.Properties['instanceUrl']
        if ($null -eq $instance) { continue }
        $candidate = [string]$instance.Value
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and [string]::Equals($candidate.TrimEnd('/'), $needle, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [string]$envItem.name
        }
    }
    throw "Could not resolve EnvironmentId for $Url via BAP. Pass -EnvironmentId explicitly."
}

function Test-EnvironmentTypeAllowed {
    <#
    .SYNOPSIS
        Validates the env sku against the AllowedEnvironmentType policy. Throws on mismatch
        unless AllowedEnvironmentType is 'Any'.
    #>
    param(
        [Parameter(Mandatory)][string]$Sku,
        [Parameter(Mandatory)][string]$Allowed
    )

    if ($Allowed -eq 'Any') {
        return
    }
    $allowedList = $Allowed.Split(',') | ForEach-Object { $_.Trim() }
    if ($Sku -in $allowedList) {
        return
    }
    throw "Environment sku '$Sku' is not in the allowed set ($Allowed). Trial/Developer/Teams environments cannot be attached to PayAsYouGo billing policies. Recreate the environment as Sandbox or Production, or pass -AllowedEnvironmentType Any to override (no credit attachment will be attempted)."
}

function Get-EnvironmentMetadataRecord {
    if ($DryRun) {
        return [ordered]@{
            OrganizationId = '00000000-0000-4000-8000-000000000000'
            FriendlyName = ([System.Uri]$EnvironmentUrl).Host
        }
    }

    $response = Invoke-DataverseRequest -Method GET -RelativeUri 'WhoAmI'
    return [ordered]@{
        OrganizationId = [string]$response.Body.OrganizationId
        FriendlyName = ([System.Uri]$EnvironmentUrl).Host
    }
}

function Get-EntityRecord {
    param([Parameter(Mandatory)][string]$LogicalName)

    if ($DryRun) {
        return [ordered]@{ LogicalName = $LogicalName; EntitySetName = ($LogicalName + 's'); PrimaryIdAttribute = ($LogicalName + 'id') }
    }

    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("EntityDefinitions(LogicalName='{0}')?`$select=LogicalName,EntitySetName,PrimaryIdAttribute" -f $LogicalName) -AllowNotFound
    if ($null -eq $response) {
        return $null
    }

    return $response.Body
}

function Test-EntityPresence {
    param([Parameter(Mandatory)][string]$LogicalName)

    $record = Get-EntityRecord -LogicalName $LogicalName
    return ($null -ne $record)
}

function Test-EntityColumnSet {
    param(
        [Parameter(Mandatory)][string]$LogicalName,
        [Parameter(Mandatory)][string[]]$RequiredColumn
    )

    if ($DryRun) {
        return $true
    }

    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("EntityDefinitions(LogicalName='{0}')/Attributes?`$select=LogicalName" -f $LogicalName)
    $actual = @($response.Body.value | ForEach-Object { [string]$_.LogicalName })
    foreach ($column in $RequiredColumn) {
        if ($column -notin $actual) {
            return $false
        }
    }

    return $true
}

function Test-GlobalOptionSetPresence {
    param([Parameter(Mandatory)][string]$Name)

    if ($DryRun) {
        return $true
    }

    # Dataverse rejects $filter on GlobalOptionSetDefinitions ('not supported',
    # HTTP 405). Use direct key access with -AllowNotFound instead.
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("GlobalOptionSetDefinitions(Name='{0}')?`$select=Name" -f $Name) -AllowNotFound
    return $null -ne $response
}

function Get-SolutionRecord {
    param([Parameter(Mandatory)][string]$UniqueName)

    $filter = ConvertTo-ODataStringLiteral -Value $UniqueName
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("solutions?`$select=solutionid,uniquename,friendlyname,version&`$filter=uniquename eq $filter")
    return $response.Body.value | Select-Object -First 1
}

function Get-EnvironmentVariableDefinitionRecord {
    param([Parameter(Mandatory)][string]$SchemaName)

    $filter = ConvertTo-ODataStringLiteral -Value $SchemaName
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("environmentvariabledefinitions?`$select=environmentvariabledefinitionid,schemaname,displayname,defaultvalue,type&`$filter=schemaname eq $filter")
    return $response.Body.value | Select-Object -First 1
}

function Get-EnvironmentVariableValueRecord {
    param([Parameter(Mandatory)][string]$SchemaName)

    $filter = ConvertTo-ODataStringLiteral -Value $SchemaName
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("environmentvariablevalues?`$select=environmentvariablevalueid,schemaname,value&`$filter=schemaname eq $filter")
    return $response.Body.value | Select-Object -First 1
}

function Get-EnvironmentVariableCurrentValue {
    param([Parameter(Mandatory)][string]$SchemaName)

    $record = Get-EnvironmentVariableValueRecord -SchemaName $SchemaName
    if ($null -eq $record) {
        return $null
    }

    return [string]$record.value
}

function Set-EnvironmentVariableCurrentValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SchemaName,
        [Parameter(Mandatory)][string]$Value
    )

    $definition = Get-EnvironmentVariableDefinitionRecord -SchemaName $SchemaName
    if ($null -eq $definition) {
        throw "Environment variable definition '$SchemaName' was not found. Run provision_solution_shell.ps1 first."
    }

    $current = Get-EnvironmentVariableValueRecord -SchemaName $SchemaName
    if ($null -ne $current) {
        if ([string]$current.value -eq $Value) {
            return 'Unchanged'
        }

        if ($PSCmdlet.ShouldProcess($SchemaName, 'Update environment variable current value')) {
            Invoke-DataverseRequest -Method PATCH -RelativeUri ("environmentvariablevalues({0})" -f $current.environmentvariablevalueid) -Body @{ value = $Value } | Out-Null
        }

        return 'Updated'
    }

    if ($PSCmdlet.ShouldProcess($SchemaName, 'Create environment variable current value')) {
        Invoke-DataverseRequest -Method POST -RelativeUri 'environmentvariablevalues' -Body @{
            schemaname = $SchemaName
            value = $Value
            'EnvironmentVariableDefinitionId@odata.bind' = "/environmentvariabledefinitions($($definition.environmentvariabledefinitionid))"
        } | Out-Null
    }

    return 'Created'
}

function Get-ConnectionReferenceRecord {
    param([Parameter(Mandatory)][string]$LogicalName)

    $filter = ConvertTo-ODataStringLiteral -Value $LogicalName
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("connectionreferences?`$select=connectionreferenceid,connectionreferencelogicalname,connectionreferencedisplayname&`$filter=connectionreferencelogicalname eq $filter")
    return $response.Body.value | Select-Object -First 1
}

function Get-ReviewerSpecRecord {
    if (-not (Test-Path -LiteralPath $script:ReviewerSpecPath)) {
        throw "Reviewer app spec was not found: $script:ReviewerSpecPath"
    }

    return Get-Content -LiteralPath $script:ReviewerSpecPath -Raw | ConvertFrom-Json -AsHashtable
}

function Get-ReviewerAppRecord {
    param([Parameter(Mandatory)][hashtable]$Spec)

    $filter = ConvertTo-ODataStringLiteral -Value ([string]$Spec.appDisplayName)
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("appmodules?`$select=appmoduleid,name,uniquename&`$filter=name eq $filter")
    return $response.Body.value | Select-Object -First 1
}

function Get-RoleRecord {
    param([Parameter(Mandatory)][string]$Name)

    $filter = ConvertTo-ODataStringLiteral -Value $Name
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("roles?`$select=roleid,name&`$filter=name eq $filter")
    return $response.Body.value | Select-Object -First 1
}

function Get-PortalSiteStatus {
    $pac = Get-Command -Name 'pac' -ErrorAction SilentlyContinue
    if ($null -eq $pac) {
        return [pscustomobject]@{ Found = $false; Detail = 'PAC CLI is not installed.' }
    }

    if ($DryRun) {
        return [pscustomobject]@{ Found = $false; Detail = 'Dry-run only.' }
    }

    $output = & $pac.Source pages list --environment $EnvironmentUrl -v 2>&1
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{ Found = $false; Detail = ($output -join ' ') }
    }

    $line = $output | Where-Object { $_ -match 'agent-intake' } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$line)) {
        return [pscustomobject]@{ Found = $false; Detail = 'Site agent-intake was not listed by pac pages list.' }
    }

    return [pscustomobject]@{ Found = $true; Detail = ([string]$line).Trim() }
}

function Get-OverrideValue {
    param([Parameter(Mandatory)][string]$Name)

    $item = Get-Item -Path ("Env:{0}" -f $Name) -ErrorAction SilentlyContinue
    if ($null -eq $item -or [string]::IsNullOrWhiteSpace($item.Value)) {
        return $null
    }

    return $item.Value.Trim()
}

function Get-PolicyDocument {
    return Get-Content -LiteralPath $script:PolicyTablesPath -Raw | ConvertFrom-Yaml
}

function ConvertTo-RedactedCommand {
    <#
    .SYNOPSIS
        Returns a copy of the command array with values following sensitive
        flags replaced by ***REDACTED*** so the command line can be safely
        echoed to stdout / CI logs without leaking bearer tokens or secrets.
    #>
    param([Parameter(Mandatory)][string[]]$Command)

    $redacted = @()
    $skipNext = $false
    foreach ($part in $Command) {
        if ($skipNext) {
            $redacted += '***REDACTED***'
            $skipNext = $false
            continue
        }
        $redacted += $part
        if ($part -match '^-{1,2}(access[-_]?token|client[-_]?secret|password|token)$') {
            $skipNext = $true
        }
    }
    return $redacted
}

function Invoke-PowerShellChildScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string[]]$Argument,
        [int[]]$AllowedExitCode = @(0)
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($ScriptPath)
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        throw "Required script was not found: $resolvedPath"
    }

    $command = @('pwsh', '-NoLogo', '-NoProfile', '-File', $resolvedPath) + $Argument
    Write-Info ((ConvertTo-RedactedCommand -Command $command) -join ' ')
    $output = & $command[0] @($command[1..($command.Count - 1)]) 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin $AllowedExitCode) {
        throw "Child PowerShell script failed ($resolvedPath): $($output -join ' ')"
    }

    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join [Environment]::NewLine) }
}

function Invoke-PythonChildScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string[]]$Argument,
        [int[]]$AllowedExitCode = @(0)
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($ScriptPath)
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        throw "Required script was not found: $resolvedPath"
    }

    $python = Get-PythonCommand
    $command = @($python, $resolvedPath) + $Argument
    Write-Info ((ConvertTo-RedactedCommand -Command $command) -join ' ')
    $output = & $command[0] @($command[1..($command.Count - 1)]) 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin $AllowedExitCode) {
        throw "Child Python script failed ($resolvedPath): $($output -join ' ')"
    }

    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join [Environment]::NewLine) }
}

function Get-StructuredOutputFile {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Test-Path -LiteralPath $script:RuntimeRoot)) {
        New-Item -ItemType Directory -Path $script:RuntimeRoot | Out-Null
    }

    return Join-Path -Path $script:RuntimeRoot -ChildPath $Name
}

function Test-PreflightStage {
    $pythonVersion = Test-PythonVersion
    Test-PythonPackage -ModuleName 'requests' -FriendlyName 'requests'
    Test-PythonPackage -ModuleName 'yaml' -FriendlyName 'pyyaml'
    Test-PythonPackage -ModuleName 'jsonschema' -FriendlyName 'jsonschema'
    Test-PythonPackage -ModuleName 'azure.identity' -FriendlyName 'azure-identity'
    Test-PythonPackage -ModuleName 'msal' -FriendlyName 'msal'

    $pacVersion = Get-CommandVersionText -Name 'pac' -Arguments @('--version')
    if ([string]::IsNullOrWhiteSpace($pacVersion)) {
        throw 'Power Platform CLI (pac) is required.'
    }

    $azVersion = Get-CommandVersionText -Name 'az' -Arguments @('--version')
    if ([string]::IsNullOrWhiteSpace($azVersion)) {
        throw 'Azure CLI (az) is required.'
    }

    $null = Test-ModuleVersion -ModuleName 'Az.Accounts' -MinimumVersion ([version]'2.0.0')
    $null = Test-ModuleVersion -ModuleName 'powershell-yaml' -MinimumVersion ([version]'0.4.0')
    
    if (-not $SkipPurviewLabel) {
        $null = Test-ModuleVersion -ModuleName 'ExchangeOnlineManagement' -MinimumVersion ([version]'3.2.0')
    } else {
        Write-Info 'ExchangeOnlineManagement module check skipped (Purview label creation disabled with -SkipPurviewLabel).'
    }
    
    $teamsModule = Test-ModuleVersion -ModuleName 'MicrosoftTeams' -MinimumVersion ([version]'5.0.0') -Optional
    if (-not $teamsModule.Present) {
        Write-WarnMessage 'MicrosoftTeams is optional. Teams-specific manual checks may be required if it is absent.'
    }

    if (-not (Test-Path -LiteralPath $script:PolicyTablesPath)) {
        throw "Policy table file was not found: $script:PolicyTablesPath"
    }

    $authSummary = Initialize-AzCliContext
    $pacSummary = Initialize-PacContext
    $pacSelection = Select-PacEnvironment
    $script:EnvironmentMetadata = Get-EnvironmentMetadataRecord
    $null = Get-DataverseToken

    $billingSummary = $null
    if ($AuthMode -eq 'AzCli') {
        $resolvedEnvId = if ([string]::IsNullOrWhiteSpace($EnvironmentId)) { Get-EnvironmentIdByUrl -Url $EnvironmentUrl } else { $EnvironmentId }
        $envSku = Get-EnvironmentSkuFromBap -EnvironmentId $resolvedEnvId
        Write-Info "Environment sku: $envSku (id: $resolvedEnvId)"
        Test-EnvironmentTypeAllowed -Sku $envSku -Allowed $AllowedEnvironmentType

        if (-not [string]::IsNullOrWhiteSpace($BillingPolicyId)) {
            $attachResult = Add-BillingPolicyAttachment -BillingPolicyId $BillingPolicyId -EnvironmentId $resolvedEnvId
            Write-Info "Billing-policy attachment: $attachResult (policy: $BillingPolicyId)"
            $billingSummary = [pscustomobject]@{ PolicyId = $BillingPolicyId; EnvironmentId = $resolvedEnvId; State = $attachResult }
        }
        else {
            Write-WarnMessage 'No -BillingPolicyId provided. Skipping Copilot/AI Builder credit attachment. Pass -BillingPolicyId or set billing.policyId in lab/config.local.json to enable.'
        }
    }
    else {
        Write-WarnMessage "AuthMode '$AuthMode' is not Azure CLI; skipping environment-type and billing-policy validation (Azure CLI is required for the BAP/PowerPlatform admin APIs)."
    }

    return [pscustomobject]@{
        Status = 'Success'
        Detail = ('Python {0}; PAC {1}; auth ok; organization {2}' -f $pythonVersion, $pacVersion, $script:EnvironmentMetadata.OrganizationId)
        Auth = $authSummary
        Pac = $pacSummary
        PacSelection = $pacSelection
        Billing = $billingSummary
    }
}

function Test-SchemaStage {
    $schemaScript = Join-Path -Path $PSScriptRoot -ChildPath 'create_fsi_intake_dataverse_schema.py'
    $arguments = @('--environment-url', $EnvironmentUrl, '--access-token', (Get-DataverseToken -Force))
    if ($DryRun) {
        $arguments += '--dry-run'
    }
    $null = Invoke-PythonChildScript -ScriptPath $schemaScript -Argument $arguments
    $docArguments = @('--output-docs', (Join-Path -Path $script:SolutionRoot -ChildPath 'docs\dataverse-schema.md'))
    $null = Invoke-PythonChildScript -ScriptPath $schemaScript -Argument $docArguments

    foreach ($tableName in $script:TableNameList) {
        if (-not (Test-EntityPresence -LogicalName $tableName)) {
            throw "Expected Dataverse table '$tableName' was not found after schema deployment."
        }
        if (-not (Test-EntityColumnSet -LogicalName $tableName -RequiredColumn $script:KeyColumnMap[$tableName])) {
            throw "Expected columns were missing from '$tableName'."
        }
    }

    foreach ($optionSetName in $script:OptionSetNameList) {
        if (-not (Test-GlobalOptionSetPresence -Name $optionSetName)) {
            throw "Expected global option set '$optionSetName' was not found."
        }
    }

    return [pscustomobject]@{
        Status = 'Success'
        Detail = 'All 9 tables, key columns, and global option sets were validated.'
    }
}

function Test-SolutionShellStage {
    $shellScript = Join-Path -Path $PSScriptRoot -ChildPath 'provision_solution_shell.ps1'
    $graphApiId = Get-OverrideValue -Name 'AGENT_INTAKE_GRAPH_CUSTOM_CONNECTOR_API_ID'
    if ($DryRun) {
        if (-not (Test-Path -LiteralPath $shellScript)) {
            throw "Required script was not found: $shellScript"
        }
        $detail = 'Dry-run: would invoke provision_solution_shell.ps1 and validate the solution shell, environment variables, and connection references.'
        if (-not [string]::IsNullOrWhiteSpace($graphApiId)) {
            $detail += ' Graph custom connector override supplied.'
        }
        return [pscustomobject]@{ Status = 'Success'; Detail = $detail }
    }

    $arguments = @('-EnvironmentUrl', $EnvironmentUrl, '-AccessToken', (Get-DataverseToken -Force))
    if (-not [string]::IsNullOrWhiteSpace($graphApiId)) {
        $arguments += @('-GraphCustomConnectorApiId', $graphApiId)
    }
    $result = Invoke-PowerShellChildScript -ScriptPath $shellScript -Argument $arguments

    $solution = Get-SolutionRecord -UniqueName 'FSIAgentIntake'
    if ($null -eq $solution) {
        throw 'The FSIAgentIntake solution shell was not found after provisioning.'
    }

    foreach ($schemaName in $script:EnvVarSchemaNameList) {
        if ($null -eq (Get-EnvironmentVariableDefinitionRecord -SchemaName $schemaName)) {
            throw "Environment variable definition '$schemaName' was not created by provision_solution_shell.ps1."
        }
    }

    foreach ($logicalName in $script:ConnectionReferenceNameList) {
        if ($null -eq (Get-ConnectionReferenceRecord -LogicalName $logicalName)) {
            throw "Connection reference '$logicalName' was not created by provision_solution_shell.ps1."
        }
    }

    $status = if ($result.Output -match 'MANUAL STEP REQUIRED') { 'ManualFallback' } else { 'Success' }
    return [pscustomobject]@{
        Status = $status
        Detail = 'Solution shell, environment variables, and standard connection references are present.'
    }
}

function Test-IdentityStage {
    $labelSkipped = $false
    $labelOutput = Get-StructuredOutputFile -Name 'retention-label.json'
    $blueprintOutput = Get-StructuredOutputFile -Name 'agent-blueprint.json'
    $consentOutput = Get-StructuredOutputFile -Name 'entra-agent-id-ready.json'
    $labelScript = Join-Path -Path $PSScriptRoot -ChildPath 'setup_purview_retention_label.py'
    $blueprintScript = Join-Path -Path $PSScriptRoot -ChildPath 'setup_agent_identity_blueprint.py'
    $consentScript = Join-Path -Path $PSScriptRoot -ChildPath 'setup_entra_agent_id.py'
    $purviewProbe = Join-Path -Path $PSScriptRoot -ChildPath 'autodetect_purview.py'
    $policy = Get-PolicyDocument

    if ($DryRun) {
        $requiredScripts = if ($SkipPurviewLabel) {
            @($blueprintScript, $consentScript, $purviewProbe)
        } else {
            @($labelScript, $blueprintScript, $consentScript, $purviewProbe)
        }
        foreach ($requiredScript in $requiredScripts) {
            if (-not (Test-Path -LiteralPath $requiredScript)) {
                throw "Required script was not found: $requiredScript"
            }
        }
        $dryRunDetail = if ($SkipPurviewLabel) {
            'Dry-run: would prepare blueprint output at {0}, consent output at {1} (Purview label skipped).' -f $blueprintOutput, $consentOutput
        } else {
            'Dry-run: would prepare Purview label output at {0}, blueprint output at {1}, and consent output at {2} for label {3}.' -f $labelOutput, $blueprintOutput, $consentOutput, [string]$policy.retention_labels.tier_1
        }
        return [pscustomobject]@{
            Status = 'Success'
            Detail = $dryRunDetail
        }
    }

    if (-not $SkipPurviewLabel) {
        $labelArguments = @('--output', $labelOutput)
        $adminUpn = Get-OverrideValue -Name 'AGENT_INTAKE_PURVIEW_ADMIN_UPN'
        if (-not [string]::IsNullOrWhiteSpace($adminUpn)) {
            $labelArguments += @('--admin-upn', $adminUpn)
        }
        if ($DryRun) {
            $labelArguments += '--dry-run'
        }
        $null = Invoke-PythonChildScript -ScriptPath $labelScript -Argument $labelArguments
    } else {
        $labelSkipped = $true
    }

    $blueprintArguments = @('--token-source', (Get-PythonTokenSource), '--output', $blueprintOutput)
    $blueprintSponsor = Get-OverrideValue -Name 'AGENT_INTAKE_BLUEPRINT_SPONSOR_UPN'
    if (-not [string]::IsNullOrWhiteSpace($blueprintSponsor)) {
        $blueprintArguments += @('--sponsor-upn', $blueprintSponsor)
    }
    if ($DryRun) {
        $blueprintArguments += '--dry-run'
    }
    $blueprintResult = Invoke-PythonChildScript -ScriptPath $blueprintScript -Argument $blueprintArguments -AllowedExitCode @(0, 2)

    $consentArguments = @('--check-consent', '--token-source', (Get-PythonTokenSource), '--output', $consentOutput)
    $null = Invoke-PythonChildScript -ScriptPath $consentScript -Argument $consentArguments

    $purviewArguments = @('--label-name', [string]$policy.retention_labels.tier_1, '--token-source', (Get-PythonTokenSource))
    $purviewResult = Invoke-PythonChildScript -ScriptPath $purviewProbe -Argument $purviewArguments -AllowedExitCode @(0, 2)

    $status = 'Success'
    $detailParts = [System.Collections.Generic.List[string]]::new()
    
    if ($labelSkipped) {
        $detailParts.Add('Purview retention label step skipped (-SkipPurviewLabel).') | Out-Null
    } else {
        $detailParts.Add('Retention label workflow invoked.') | Out-Null
        if ($purviewResult.ExitCode -eq 0) {
            $detailParts.Add('Purview label verified.') | Out-Null
        }
        else {
            $status = 'Warning'
            $detailParts.Add('Purview label could not be verified automatically; check delegated Purview permissions.') | Out-Null
        }
    }
    
    if ($blueprintResult.ExitCode -eq 0) {
        $detailParts.Add('Blueprint registration verified.') | Out-Null
    }
    else {
        $status = 'Warning'
        $detailParts.Add('Blueprint creation used manual fallback because the tenant or caller is feature-gated.') | Out-Null
    }

    return [pscustomobject]@{
        Status = $status
        Detail = ($detailParts -join ' ')
    }
}

function Test-MakerStage {
    $makerScript = Join-Path -Path $PSScriptRoot -ChildPath 'provision_power_pages.ps1'
    if ($DryRun) {
        if (-not (Test-Path -LiteralPath $makerScript)) {
            throw "Required script was not found: $makerScript"
        }
        return [pscustomobject]@{ Status = 'ManualFallback'; Detail = 'Dry-run: would invoke provision_power_pages.ps1 and then validate the maker portal URL or record a manual fallback.' }
    }

    $arguments = @('-EnvironmentUrl', $EnvironmentUrl)
    $result = Invoke-PowerShellChildScript -ScriptPath $makerScript -Argument $arguments
    $siteStatus = Get-PortalSiteStatus
    if ($siteStatus.Found) {
        return [pscustomobject]@{
            Status = if ($result.Output -match 'MANUAL STEP REQUIRED') { 'ManualFallback' } else { 'Success' }
            Detail = ('Power Pages site discovered: {0}' -f $siteStatus.Detail)
        }
    }

    Write-ManualMessage 'Power Pages classic site creation and page binding still require the maker portal when PAC CLI cannot complete the full surface.'
    return [pscustomobject]@{
        Status = 'ManualFallback'
        Detail = $siteStatus.Detail
    }
}

function Test-ReviewerStage {
    $spec = Get-ReviewerSpecRecord
    $reviewerScript = Join-Path -Path $PSScriptRoot -ChildPath 'provision_reviewer_app.ps1'
    if ($DryRun) {
        if (-not (Test-Path -LiteralPath $reviewerScript)) {
            throw "Required script was not found: $reviewerScript"
        }
        return [pscustomobject]@{ Status = 'Success'; Detail = ('Dry-run: would invoke provision_reviewer_app.ps1 for {0} and validate {1} reviewer role(s).' -f $spec.appDisplayName, @($spec.securityRoles).Count) }
    }

    $arguments = @('-EnvironmentUrl', $EnvironmentUrl, '-AccessToken', (Get-DataverseToken -Force))
    $result = Invoke-PowerShellChildScript -ScriptPath $reviewerScript -Argument $arguments

    $solution = Get-SolutionRecord -UniqueName ([string]$spec.solutionName)
    if ($null -eq $solution) {
        throw "Reviewer app solution '$($spec.solutionName)' was not found after provisioning."
    }

    $app = Get-ReviewerAppRecord -Spec $spec
    if ($null -eq $app) {
        throw "Reviewer app '$($spec.appDisplayName)' was not found after provisioning."
    }

    foreach ($role in @($spec.securityRoles)) {
        if ($null -eq (Get-RoleRecord -Name ([string]$role.name))) {
            throw "Reviewer security role '$($role.name)' was not found after provisioning."
        }
    }

    return [pscustomobject]@{
        Status = if ($result.Output -match 'MANUAL STEP REQUIRED') { 'ManualFallback' } else { 'Success' }
        Detail = ('Reviewer app {0} and {1} roles were validated.' -f $spec.appDisplayName, @($spec.securityRoles).Count)
    }
}

function Get-PolicyHydrationValueMap {
    param(
        [Parameter(Mandatory)][hashtable]$Policy,
        [Parameter()][hashtable]$ReviewerApp
    )

    $values = [ordered]@{}
    $manualNote = [System.Collections.Generic.List[string]]::new()

    $values.fsi_intake_powerplatformenvironmenturl = $EnvironmentUrl
    $values.fsi_intake_makerportalurl = if (Get-OverrideValue -Name 'AGENT_INTAKE_MAKER_PORTAL_URL') {
        Get-OverrideValue -Name 'AGENT_INTAKE_MAKER_PORTAL_URL'
    }
    elseif (-not [string]::IsNullOrWhiteSpace((Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_makerportalurl'))) {
        Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_makerportalurl'
    }
    else {
        $manualNote.Add('fsi_intake_makerportalurl uses a placeholder until the live portal URL is known.') | Out-Null
        'https://manual-step-required.invalid/agent-intake'
    }
    $values.fsi_intake_reviewerappurl = if (Get-OverrideValue -Name 'AGENT_INTAKE_REVIEWER_APP_URL') {
        Get-OverrideValue -Name 'AGENT_INTAKE_REVIEWER_APP_URL'
    }
    elseif (-not [string]::IsNullOrWhiteSpace((Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_reviewerappurl'))) {
        Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_reviewerappurl'
    }
    elseif ($null -ne $ReviewerApp -and -not [string]::IsNullOrWhiteSpace([string]$ReviewerApp.appmoduleid)) {
        'appmodule://{0}' -f [string]$ReviewerApp.appmoduleid
    }
    else {
        $manualNote.Add('fsi_intake_reviewerappurl uses a placeholder until the customer-facing app URL is known.') | Out-Null
        'appmodule://manual-step-required'
    }
    $values.fsi_intake_mrmtargetenv = if (Get-OverrideValue -Name 'AGENT_INTAKE_MRM_TARGET_ENV') {
        Get-OverrideValue -Name 'AGENT_INTAKE_MRM_TARGET_ENV'
    }
    elseif (-not [string]::IsNullOrWhiteSpace((Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_mrmtargetenv'))) {
        Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_mrmtargetenv'
    }
    else {
        $EnvironmentUrl
    }
    $values.fsi_intake_driftdetectorenv = if (Get-OverrideValue -Name 'AGENT_INTAKE_DRIFT_DETECTOR_ENV') {
        Get-OverrideValue -Name 'AGENT_INTAKE_DRIFT_DETECTOR_ENV'
    }
    elseif (-not [string]::IsNullOrWhiteSpace((Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_driftdetectorenv'))) {
        Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_driftdetectorenv'
    }
    else {
        $EnvironmentUrl
    }
    $values.fsi_intake_retentionlabelid = if (Get-OverrideValue -Name 'AGENT_INTAKE_RETENTION_LABEL_ID') {
        Get-OverrideValue -Name 'AGENT_INTAKE_RETENTION_LABEL_ID'
    }
    elseif (-not [string]::IsNullOrWhiteSpace((Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_retentionlabelid'))) {
        Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_retentionlabelid'
    }
    else {
        [string]$Policy.retention_labels.decision_log
    }
    $values.fsi_intake_sponsorbackupgroup = if (Get-OverrideValue -Name 'AGENT_INTAKE_SPONSOR_BACKUP_GROUP') {
        Get-OverrideValue -Name 'AGENT_INTAKE_SPONSOR_BACKUP_GROUP'
    }
    elseif (-not [string]::IsNullOrWhiteSpace((Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_sponsorbackupgroup'))) {
        Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_sponsorbackupgroup'
    }
    else {
        $manualNote.Add('fsi_intake_sponsorbackupgroup uses the documented lab placeholder until the customer backup group is confirmed.') | Out-Null
        'agent-intake-sponsor-backups@example.com'
    }

    return [pscustomobject]@{
        Value = $values
        Note = ($manualNote -join ' ')
    }
}

function Test-PolicyStage {
    $policy = Get-PolicyDocument
    $reviewerSpec = Get-ReviewerSpecRecord
    if ($DryRun) {
        $planned = @($script:EnvVarSchemaNameList | Sort-Object) -join ', '
        return [pscustomobject]@{ Status = 'Success'; Detail = ('Dry-run: would hydrate environment variables: {0}. Retention label baseline: {1}.' -f $planned, [string]$policy.retention_labels.decision_log) }
    }

    $reviewerApp = Get-ReviewerAppRecord -Spec $reviewerSpec
    $hydration = Get-PolicyHydrationValueMap -Policy $policy -ReviewerApp $reviewerApp
    $changed = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $hydration.Value.GetEnumerator()) {
        $schemaName = [string]$entry.Key
        $rawValue = [string]$entry.Value
        try {
            $result = Set-EnvironmentVariableCurrentValue -SchemaName $schemaName -Value $rawValue
        }
        catch {
            $detail = "Stage 6 sub-step failed at SchemaName='$schemaName' Value='$rawValue': $($_.Exception.Message). InnerStack: $($_.ScriptStackTrace)"
            throw $detail
        }
        $changed.Add(('{0}:{1}' -f $schemaName, [string]$result)) | Out-Null
    }

    foreach ($schemaName in $script:EnvVarSchemaNameList) {
        $value = Get-EnvironmentVariableCurrentValue -SchemaName $schemaName
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Environment variable '$schemaName' is still empty after policy hydration."
        }
    }

    $status = if ([string]::IsNullOrWhiteSpace($hydration.Note)) { 'Success' } else { 'Warning' }
    return [pscustomobject]@{
        Status = $status
        Detail = (($changed -join ', ') + ' ' + $hydration.Note).Trim()
    }
}

function Invoke-SmokeStage {
    $smokeScript = Join-Path -Path $PSScriptRoot -ChildPath 'smoke_test.ps1'
    $arguments = @('-EnvironmentUrl', $EnvironmentUrl)
    if ($DryRun) {
        $arguments += '-DryRun'
    }
    $null = Invoke-PowerShellChildScript -ScriptPath $smokeScript -Argument $arguments
    return [pscustomobject]@{
        Status = 'Success'
        Detail = 'Baseline smoke test passed.'
    }
}

function Invoke-SeedStage {
    $seedScript = Join-Path -Path $PSScriptRoot -ChildPath 'seed-test-data.ps1'
    $arguments = @('-EnvironmentUrl', $EnvironmentUrl, '-RunClassifierInline')
    if ($DryRun) {
        $arguments += '-DryRun'
    }
    $null = Invoke-PowerShellChildScript -ScriptPath $seedScript -Argument $arguments

    if (-not $DryRun) {
        $fixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'seed-test-data'
        $requestIds = @(
            (Get-Content -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath 'request-express-happy.json') -Raw | ConvertFrom-Json).fsi_intakerequest.fsi_requestid,
            (Get-Content -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath 'request-standard-conditional.json') -Raw | ConvertFrom-Json).fsi_intakerequest.fsi_requestid,
            (Get-Content -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath 'request-full-parallel-board.json') -Raw | ConvertFrom-Json).fsi_intakerequest.fsi_requestid,
            (Get-Content -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath 'request-cross-border-deny.json') -Raw | ConvertFrom-Json).fsi_intakerequest.fsi_requestid,
            (Get-Content -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath 'request-sponsor-self-approval-deny.json') -Raw | ConvertFrom-Json).fsi_intakerequest.fsi_requestid
        )
        $filter = ($requestIds | ForEach-Object { "fsi_requestid eq {0}" -f (ConvertTo-ODataStringLiteral -Value ([string]$_)) }) -join ' or '
        $response = Invoke-DataverseRequest -Method GET -RelativeUri ("fsi_intakerequests?`$select=fsi_requestid&`$filter={0}" -f $filter)
        if (@($response.Body.value).Count -lt 5) {
            throw 'Seed stage did not create all expected intake request rows.'
        }
    }

    if (-not $SkipSmoke) {
        if ($DryRun) {
            return [pscustomobject]@{
                Status = 'Success'
                Detail = 'Seeded data dry-run completed. The seeded smoke gate is planned for the next live run.'
            }
        }

        $smokeScript = Join-Path -Path $PSScriptRoot -ChildPath 'smoke_test.ps1'
        $smokeArguments = @('-EnvironmentUrl', $EnvironmentUrl, '-IncludeSeededDataChecks')
        $null = Invoke-PowerShellChildScript -ScriptPath $smokeScript -Argument $smokeArguments
    }

    return [pscustomobject]@{
        Status = 'Success'
        Detail = if ($SkipSmoke) { 'Seeded data created.' } else { 'Seeded data created and seeded smoke test passed.' }
    }
}

function Show-StageSummary {
    if ($script:StageSummary.Count -gt 0) {
        Write-Output ''
        Write-Output 'Deployment summary'
        $script:StageSummary | Format-Table -AutoSize | Out-String | Write-Output
        Write-Output ('Structured log: {0}' -f $script:StructuredLogPath)
    }
}

function Show-TeardownSummary {
    if ($script:TeardownSummary.Count -gt 0) {
        Write-Output ''
        Write-Output 'Teardown summary'
        $script:TeardownSummary | Format-Table -AutoSize | Out-String | Write-Output
    }
}

function Clear-EntityData {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$LogicalName)

    $entity = $script:EntityMap[$LogicalName]
    $count = 0
    if ($DryRun) {
        Add-TeardownSummaryRecord -Component $LogicalName -Status 'Planned' -Detail 'Would remove all rows.'
        return
    }

    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("{0}?`$select={1}" -f $entity.EntitySetName, $entity.PrimaryIdAttribute)
    foreach ($record in @($response.Body.value)) {
        $id = $record[$entity.PrimaryIdAttribute]
        if ($PSCmdlet.ShouldProcess($LogicalName, 'Delete Dataverse row')) {
            Invoke-DataverseRequest -Method DELETE -RelativeUri ('{0}({1})' -f $entity.EntitySetName, $id) | Out-Null
            $count++
        }
    }

    Add-TeardownSummaryRecord -Component $LogicalName -Status 'Destroyed' -Detail ("Removed $count row(s).")
}

function Remove-EnvironmentVariableDefinition {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$SchemaName)

    $value = Get-EnvironmentVariableValueRecord -SchemaName $SchemaName
    if ($null -ne $value) {
        if ($PSCmdlet.ShouldProcess($SchemaName, 'Delete environment variable current value')) {
            Invoke-DataverseRequest -Method DELETE -RelativeUri ("environmentvariablevalues({0})" -f $value.environmentvariablevalueid) | Out-Null
        }
    }

    $definition = Get-EnvironmentVariableDefinitionRecord -SchemaName $SchemaName
    if ($null -eq $definition) {
        Add-TeardownSummaryRecord -Component $SchemaName -Status 'AlreadyAbsent' -Detail 'Environment variable definition was not present.'
        return
    }

    if ($PSCmdlet.ShouldProcess($SchemaName, 'Delete environment variable definition')) {
        Invoke-DataverseRequest -Method DELETE -RelativeUri ("environmentvariabledefinitions({0})" -f $definition.environmentvariabledefinitionid) | Out-Null
    }

    Add-TeardownSummaryRecord -Component $SchemaName -Status 'Destroyed' -Detail 'Environment variable definition and current value removed.'
}

function Remove-ConnectionReference {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$LogicalName)

    $record = Get-ConnectionReferenceRecord -LogicalName $LogicalName
    if ($null -eq $record) {
        Add-TeardownSummaryRecord -Component $LogicalName -Status 'AlreadyAbsent' -Detail 'Connection reference was not present.'
        return
    }

    if ($PSCmdlet.ShouldProcess($LogicalName, 'Delete connection reference')) {
        Invoke-DataverseRequest -Method DELETE -RelativeUri ("connectionreferences({0})" -f $record.connectionreferenceid) | Out-Null
    }

    Add-TeardownSummaryRecord -Component $LogicalName -Status 'Destroyed' -Detail 'Connection reference removed.'
}

function Remove-ReviewerComponent {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][hashtable]$ReviewerSpec)

    $app = Get-ReviewerAppRecord -Spec $ReviewerSpec
    if ($null -ne $app) {
        if ($PSCmdlet.ShouldProcess($ReviewerSpec.appDisplayName, 'Delete reviewer appmodule')) {
            Invoke-DataverseRequest -Method DELETE -RelativeUri ("appmodules({0})" -f $app.appmoduleid) | Out-Null
        }
        Add-TeardownSummaryRecord -Component ([string]$ReviewerSpec.appDisplayName) -Status 'Destroyed' -Detail 'Reviewer appmodule removed.'
    }
    else {
        Add-TeardownSummaryRecord -Component ([string]$ReviewerSpec.appDisplayName) -Status 'AlreadyAbsent' -Detail 'Reviewer appmodule was not present.'
    }

    foreach ($role in @($ReviewerSpec.securityRoles)) {
        $roleRecord = Get-RoleRecord -Name ([string]$role.name)
        if ($null -eq $roleRecord) {
            Add-TeardownSummaryRecord -Component ([string]$role.name) -Status 'AlreadyAbsent' -Detail 'Security role was not present.'
            continue
        }

        if ($PSCmdlet.ShouldProcess([string]$role.name, 'Delete reviewer security role')) {
            Invoke-DataverseRequest -Method DELETE -RelativeUri ("roles({0})" -f $roleRecord.roleid) | Out-Null
        }
        Add-TeardownSummaryRecord -Component ([string]$role.name) -Status 'Destroyed' -Detail 'Security role removed.'
    }
}

function Remove-SolutionContainer {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$SolutionName)

    $solution = Get-SolutionRecord -UniqueName $SolutionName
    if ($null -eq $solution) {
        Add-TeardownSummaryRecord -Component $SolutionName -Status 'AlreadyAbsent' -Detail 'Solution shell was not present.'
        return
    }

    $pac = Get-Command -Name 'pac' -ErrorAction SilentlyContinue
    if ($null -eq $pac) {
        Add-TeardownSummaryRecord -Component $SolutionName -Status 'ManualFallback' -Detail 'PAC CLI is required to delete the solution container.'
        return
    }

    if ($DryRun) {
        Add-TeardownSummaryRecord -Component $SolutionName -Status 'Planned' -Detail 'Would delete the solution container.'
        return
    }

    if ($PSCmdlet.ShouldProcess($SolutionName, 'Delete solution container')) {
        $output = & $pac.Source solution delete --solution-name $SolutionName --environment $EnvironmentUrl 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-TeardownSummaryRecord -Component $SolutionName -Status 'ManualFallback' -Detail ("pac solution delete failed: {0}" -f ($output -join ' '))
            return
        }
    }

    Add-TeardownSummaryRecord -Component $SolutionName -Status 'Destroyed' -Detail 'Solution container deleted.'
}

function Remove-EntityDefinition {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$LogicalName)

    if ($DryRun) {
        Add-TeardownSummaryRecord -Component $LogicalName -Status 'Planned' -Detail 'Would delete Dataverse table metadata.'
        return
    }

    $entity = Get-EntityRecord -LogicalName $LogicalName
    if ($null -eq $entity) {
        Add-TeardownSummaryRecord -Component $LogicalName -Status 'AlreadyAbsent' -Detail 'Table metadata was not present.'
        return
    }

    if ($PSCmdlet.ShouldProcess($LogicalName, 'Delete Dataverse table metadata')) {
        try {
            Invoke-DataverseRequest -Method DELETE -RelativeUri ("EntityDefinitions(LogicalName='{0}')" -f $LogicalName) | Out-Null
            Add-TeardownSummaryRecord -Component $LogicalName -Status 'Destroyed' -Detail 'Custom table metadata deleted.'
        }
        catch {
            Add-TeardownSummaryRecord -Component $LogicalName -Status 'ManualFallback' -Detail $_.Exception.Message
        }
    }
}

function Remove-OptionSetDefinition {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name)

    if ($DryRun) {
        Add-TeardownSummaryRecord -Component $Name -Status 'Planned' -Detail 'Would delete global option set metadata.'
        return
    }

    if (-not (Test-GlobalOptionSetPresence -Name $Name)) {
        Add-TeardownSummaryRecord -Component $Name -Status 'AlreadyAbsent' -Detail 'Global option set was not present.'
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Delete global option set metadata')) {
        try {
            Invoke-DataverseRequest -Method DELETE -RelativeUri ("GlobalOptionSetDefinitions(Name='{0}')" -f $Name) | Out-Null
            Add-TeardownSummaryRecord -Component $Name -Status 'Destroyed' -Detail 'Global option set deleted.'
        }
        catch {
            Add-TeardownSummaryRecord -Component $Name -Status 'ManualFallback' -Detail $_.Exception.Message
        }
    }
}

function Invoke-TeardownStage {
    $reviewerSpec = Get-ReviewerSpecRecord
    $seedScript = Join-Path -Path $PSScriptRoot -ChildPath 'seed-test-data.ps1'
    $seedArgument = @('-EnvironmentUrl', $EnvironmentUrl, '-Cleanup')
    if ($DryRun) {
        $seedArgument += '-DryRun'
    }
    $null = Invoke-PowerShellChildScript -ScriptPath $seedScript -Argument $seedArgument
    Add-TeardownSummaryRecord -Component 'seed-test-data' -Status $(if ($DryRun) { 'Planned' } else { 'Destroyed' }) -Detail 'Seeded lab data cleanup invoked.'

    foreach ($logicalName in $script:TableNameList) {
        Clear-EntityData -LogicalName $logicalName
    }

    Remove-ReviewerComponent -ReviewerSpec $reviewerSpec
    Remove-SolutionContainer -SolutionName ([string]$reviewerSpec.solutionName)

    $siteStatus = Get-PortalSiteStatus
    if ($siteStatus.Found) {
        Add-TeardownSummaryRecord -Component 'Power Pages site' -Status 'ManualFallback' -Detail 'PAC CLI cannot delete the classic site and page binding reliably. Remove the site or page in the maker portal.'
    }
    else {
        Add-TeardownSummaryRecord -Component 'Power Pages site' -Status 'AlreadyAbsent' -Detail 'No site named agent-intake was discovered by PAC CLI.'
    }

    foreach ($schemaName in $script:EnvVarSchemaNameList) {
        Remove-EnvironmentVariableDefinition -SchemaName $schemaName
    }

    foreach ($logicalName in $script:ConnectionReferenceNameList) {
        Remove-ConnectionReference -LogicalName $logicalName
    }

    foreach ($logicalName in $script:TableNameList) {
        Remove-EntityDefinition -LogicalName $logicalName
    }

    foreach ($name in $script:OptionSetNameList) {
        Remove-OptionSetDefinition -Name $name
    }

    Remove-SolutionContainer -SolutionName 'FSIAgentIntake'
    Add-TeardownSummaryRecord -Component 'Purview retention labels' -Status 'ManualDecisionRequired' -Detail 'FSI-AgentIntake-7yr and FSI-AgentIntake-7yr-WORM were left in place because tenant-wide labels may still be referenced outside agent-intake. Remove them only after a records-management review.'
    Add-TeardownSummaryRecord -Component 'Agent identity blueprint' -Status 'ManualDecisionRequired' -Detail 'The default blueprint can be shared across multiple agents. Delete it through Microsoft Graph only after confirming that no other agent depends on it.'
    return [pscustomobject]@{ Status = 'Success'; Detail = 'Teardown completed with manual follow-up items recorded.' }
}

try {
    if (Test-Path -LiteralPath $script:RuntimeRoot) {
        Remove-Item -LiteralPath $script:RuntimeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($Teardown) {
        $script:EnvironmentMetadata = Get-EnvironmentMetadataRecord
        $null = Initialize-AzCliContext
        $null = Initialize-PacContext
        $null = Select-PacEnvironment
        $null = Get-DataverseToken
        $null = Invoke-StageAction -Stage 'Teardown' -FailureCode $script:ExitCodeMap.Teardown -Action { Invoke-TeardownStage }
        Show-TeardownSummary
        Show-StageSummary
        exit 0
    }

    $null = Invoke-StageAction -Stage 'Stage 0 - Preflight' -FailureCode $script:ExitCodeMap.Preflight -Action { Test-PreflightStage }
    $null = Invoke-StageAction -Stage 'Stage 1 - Schema' -FailureCode $script:ExitCodeMap.Schema -Action { Test-SchemaStage }
    $null = Invoke-StageAction -Stage 'Stage 2 - Solution shell' -FailureCode $script:ExitCodeMap.Shell -Action { Test-SolutionShellStage }
    $null = Invoke-StageAction -Stage 'Stage 3 - Identity and records' -FailureCode $script:ExitCodeMap.Identity -Action { Test-IdentityStage }
    $null = Invoke-StageAction -Stage 'Stage 4 - Maker surface' -FailureCode $script:ExitCodeMap.Maker -Action { Test-MakerStage }
    $null = Invoke-StageAction -Stage 'Stage 5 - Reviewer app' -FailureCode $script:ExitCodeMap.Reviewer -Action { Test-ReviewerStage }
    $null = Invoke-StageAction -Stage 'Stage 6 - Policy hydration' -FailureCode $script:ExitCodeMap.Policy -Action { Test-PolicyStage }
    if (-not $SkipSmoke) {
        $null = Invoke-StageAction -Stage 'Stage 7 - Smoke test' -FailureCode $script:ExitCodeMap.Smoke -Action { Invoke-SmokeStage }
    }
    else {
        Add-StageSummaryRecord -Stage 'Stage 7 - Smoke test' -Status 'Skipped' -DurationMs 0 -Detail 'SkipSmoke was specified.'
    }
    if ($SeedTestData) {
        $null = Invoke-StageAction -Stage 'Stage 8 - Seed test data' -FailureCode $script:ExitCodeMap.Seed -Action { Invoke-SeedStage }
    }
    else {
        Add-StageSummaryRecord -Stage 'Stage 8 - Seed test data' -Status 'Skipped' -DurationMs 0 -Detail 'SeedTestData was not specified.'
    }

    Show-StageSummary
    exit 0
}
finally {
    if (Test-Path -LiteralPath $script:RuntimeRoot) {
        Remove-Item -LiteralPath $script:RuntimeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
