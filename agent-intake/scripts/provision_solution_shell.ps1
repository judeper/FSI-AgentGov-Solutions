#Requires -Version 7.0

<#
.SYNOPSIS
Provision the unmanaged `FSIAgentIntake` solution shell.

.DESCRIPTION
Uses PAC CLI for authentication verification, environment selection, solution
inventory, solution-component registration, and publish. Uses the Dataverse Web
API for publisher, solution, environment-variable, and connection-reference
upserts because current PAC CLI documentation covers solution-component add/list
operations but does not document first-party commands that create environment
variable definitions/values or connection-reference definitions directly.

Verified references:
- https://learn.microsoft.com/power-platform/developer/cli/reference/auth
- https://learn.microsoft.com/power-platform/developer/cli/reference/env
- https://learn.microsoft.com/power-platform/developer/cli/reference/solution
- https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/publisher
- https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/solution
- https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/environmentvariabledefinition
- https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/environmentvariablevalue
- https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/connectionreference

The script is idempotent. Re-running it updates definitions, current values,
and solution-component membership when those records already exist.

Any step PAC CLI or Dataverse can't complete reliably is surfaced with a line
prefixed `MANUAL STEP REQUIRED:` so an admin can finish it in the maker UI.

.PARAMETER EnvironmentUrl
Target Dataverse environment URL, for example https://contoso.crm.dynamics.com.

.PARAMETER PublisherPrefix
Customization prefix used by the solution publisher.

.PARAMETER PublisherName
Publisher unique name and default friendly name.

.PARAMETER SolutionName
Unmanaged solution unique name.

.PARAMETER SolutionDisplayName
Unmanaged solution display name.

.PARAMETER SolutionVersion
Solution version used when the solution is created for the first time.

.PARAMETER PublisherOptionValuePrefix
Option-value prefix used only when the publisher must be created.

.PARAMETER EnvVarValues
Optional hashtable of current values keyed by environment-variable schema name.
Definitions are always created or updated; current values are only created or
updated when a matching key is present in this hashtable.

.PARAMETER AccessToken
Optional Dataverse bearer token. If omitted, the script tries DATAVERSE_ACCESS_TOKEN,
PAC_ACCESS_TOKEN, or Azure CLI cached auth.

.PARAMETER GraphCustomConnectorApiId
Optional Microsoft Graph custom-connector API ID. Pass either `shared_<name>` or
`/providers/Microsoft.PowerApps/apis/shared_<name>`. If omitted, the script creates
all standard connection references and emits a `MANUAL STEP REQUIRED:` line for the
Graph custom-connector reference.

.PARAMETER DryRun
Print planned PAC CLI and Dataverse Web API actions without making changes.

.EXAMPLE
pwsh .\scripts\provision_solution_shell.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com

.EXAMPLE
pwsh .\scripts\provision_solution_shell.ps1 `
  -EnvironmentUrl https://contoso.crm.dynamics.com `
  -EnvVarValues @{ fsi_intake_makerportalurl = 'https://contoso.powerpagesportals.com/agent-intake' }

.EXAMPLE
pwsh .\scripts\provision_solution_shell.ps1 `
  -EnvironmentUrl https://contoso.crm.dynamics.com `
  -GraphCustomConnectorApiId shared_contosoGraphConnector `
  -DryRun
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'PSScriptAnalyzer honors this rule at script or function scope; flagged compatibility parameters below include individual justifications.'
)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [Parameter()]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9]{1,7}$')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [string]$PublisherPrefix = 'fsi',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PublisherName = 'FSIPublisher',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SolutionName = 'FSIAgentIntake',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SolutionDisplayName = 'FSI Agent Intake',

    [Parameter()]
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [string]$SolutionVersion = '1.0.0.0',

    [Parameter()]
    [ValidateRange(10000, 99999)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [int]$PublisherOptionValuePrefix = 58110,

    [Parameter()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
    )]
    [hashtable]$EnvVarValues,

    [Parameter()]
    [string]$AccessToken,

    [Parameter()]
    [string]$GraphCustomConnectorApiId,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BaseApiUrl = '{0}/api/data/v9.2/' -f $EnvironmentUrl.TrimEnd('/')
$script:PacCommandsUsed = [System.Collections.Generic.List[string]]::new()
$script:ManualSteps = [System.Collections.Generic.List[string]]::new()
$script:SummaryRows = [System.Collections.Generic.List[object]]::new()

$tableSpecs = @(
    @{ LogicalName = 'fsi_intakerequest'; SchemaName = 'fsi_IntakeRequest'; DisplayName = 'Intake Request' },
    @{ LogicalName = 'fsi_intakedatasource'; SchemaName = 'fsi_IntakeDataSource'; DisplayName = 'Intake Data Source' },
    @{ LogicalName = 'fsi_intakerisksignal'; SchemaName = 'fsi_IntakeRiskSignal'; DisplayName = 'Intake Risk Signal' },
    @{ LogicalName = 'fsi_intakereview'; SchemaName = 'fsi_IntakeReview'; DisplayName = 'Intake Review' },
    @{ LogicalName = 'fsi_intakeapproval'; SchemaName = 'fsi_IntakeApproval'; DisplayName = 'Intake Approval' },
    @{ LogicalName = 'fsi_intakedecisionlog'; SchemaName = 'fsi_IntakeDecisionLog'; DisplayName = 'Intake Decision Log' },
    @{ LogicalName = 'fsi_intakesponsorship'; SchemaName = 'fsi_IntakeSponsorship'; DisplayName = 'Intake Sponsorship' },
    @{ LogicalName = 'fsi_intakeauditevent'; SchemaName = 'fsi_IntakeAuditEvent'; DisplayName = 'Intake Audit Event' },
    @{ LogicalName = 'fsi_intakeretentionrecord'; SchemaName = 'fsi_IntakeRetentionRecord'; DisplayName = 'Intake Retention Record' }
)

$optionSetNames = @(
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

$envVarDefinitions = @(
    @{ SchemaName = 'fsi_intake_powerplatformenvironmenturl'; DisplayName = 'Agent Intake - Power Platform Environment URL'; Description = 'Dataverse environment URL used by agent-intake flows for API callbacks and deep links.'; DefaultValue = ''; Type = 100000000 },
    @{ SchemaName = 'fsi_intake_makerportalurl'; DisplayName = 'Agent Intake - Maker Portal URL'; Description = 'Public Power Pages URL for the maker intake experience.'; DefaultValue = ''; Type = 100000000 },
    @{ SchemaName = 'fsi_intake_reviewerappurl'; DisplayName = 'Agent Intake - Reviewer App URL'; Description = 'Model-driven reviewer app URL opened from reviewer adaptive cards.'; DefaultValue = ''; Type = 100000000 },
    @{ SchemaName = 'fsi_intake_mrmtargetenv'; DisplayName = 'Agent Intake - MRM Target Environment'; Description = 'Environment URL or wrapper endpoint used for model-risk-management handoff.'; DefaultValue = ''; Type = 100000000 },
    @{ SchemaName = 'fsi_intake_driftdetectorenv'; DisplayName = 'Agent Intake - Drift Detector Environment'; Description = 'Environment URL or wrapper endpoint used for the post-approval drift handoff.'; DefaultValue = ''; Type = 100000000 },
    @{ SchemaName = 'fsi_intake_retentionlabelid'; DisplayName = 'Agent Intake - Retention Label ID'; Description = 'Purview retention-label identifier used by decision-pack and retention workflows.'; DefaultValue = ''; Type = 100000000 },
    @{ SchemaName = 'fsi_intake_sponsorbackupgroup'; DisplayName = 'Agent Intake - Sponsor Backup Group'; Description = 'Backup Microsoft 365 group, DL, or UPN used when sponsor escalation cannot route to the manager.'; DefaultValue = ''; Type = 100000000 }
)

$connectionReferenceDefinitions = @(
    @{ LogicalName = 'fsi_cr_dataverse_agentintake'; DisplayName = 'Dataverse - Agent Intake'; ConnectorApiId = 'shared_commondataserviceforapps'; Description = 'Dataverse connection for request, review, decision-log, and audit-event CRUD.' },
    @{ LogicalName = 'fsi_cr_teams_agentintake'; DisplayName = 'Teams - Agent Intake'; ConnectorApiId = 'shared_teams'; Description = 'Microsoft Teams connection for sponsor cards, reviewer cards, and escalation notices.' },
    @{ LogicalName = 'fsi_cr_office365_agentintake'; DisplayName = 'Office 365 Outlook - Agent Intake'; ConnectorApiId = 'shared_office365'; Description = 'Office 365 Outlook connection for reviewer reminders and mail fallback.' },
    @{ LogicalName = 'fsi_cr_http_agentintake'; DisplayName = 'HTTP with Microsoft Entra ID - Agent Intake'; ConnectorApiId = 'shared_webcontents'; Description = 'HTTP with Microsoft Entra ID connection for classifier, MRM, registry, drift, and retention wrapper calls.' }
)

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnMessage {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Add-ManualStep {
    param([Parameter(Mandatory = $true)][string]$Message)

    if (-not $script:ManualSteps.Contains($Message)) {
        $script:ManualSteps.Add($Message) | Out-Null
    }

    Write-WarnMessage "MANUAL STEP REQUIRED: $Message"
}

function Add-SummaryRow {
    param(
        [Parameter(Mandatory = $true)][string]$Area,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $script:SummaryRows.Add([pscustomobject]@{
        Area   = $Area
        Status = $Status
        Detail = $Detail
    }) | Out-Null
}

function Test-PacInstalled {
    try {
        $null = Get-Command pac -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-PacVersion {
    if (-not (Test-PacInstalled)) {
        return $null
    }

    $raw = & pac 2>&1
    $match = [regex]::Match(($raw -join "`n"), 'Version:\s*([^\r\n]+)')
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return 'unknown'
}

function Invoke-PacCommand {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter()][switch]$ExpectJson
    )

    $display = 'pac ' + ($Arguments -join ' ')
    $script:PacCommandsUsed.Add($display) | Out-Null
    Write-Info ("{0}: {1}" -f $Description, $display)

    if ($DryRun) {
        if ($ExpectJson) {
            return @()
        }

        return ''
    }

    $raw = & pac @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($raw | ForEach-Object { "$_" }) -join "`n"
    if ($exitCode -ne 0) {
        throw "$Description failed (exit $exitCode): $text"
    }

    if ($ExpectJson -or $text.Trim().StartsWith('[') -or $text.Trim().StartsWith('{')) {
        if ([string]::IsNullOrWhiteSpace($text)) {
            return @()
        }

        return ($text | ConvertFrom-Json)
    }

    return $text
}

function Test-PacAuthentication {
    if ($DryRun) {
        return
    }

    $null = & pac auth who --json 2>&1
    if ($LASTEXITCODE -eq 0) {
        return
    }

    Write-WarnMessage 'PAC CLI is not currently authenticated. Attempting to create an auth profile now.'
    if ($env:IDENTITY_ENDPOINT -or $env:MSI_ENDPOINT -or $env:AZURE_CLIENT_ID) {
        Invoke-PacCommand -Arguments @('auth', 'create', '--managedIdentity', '--environment', $EnvironmentUrl) -Description 'Create PAC auth profile via managed identity' | Out-Null
        return
    }

    Invoke-PacCommand -Arguments @('auth', 'create', '--deviceCode', '--environment', $EnvironmentUrl) -Description 'Create PAC auth profile via device code' | Out-Null
}

function Select-PacEnvironment {
    Invoke-PacCommand -Arguments @('env', 'select', '--environment', $EnvironmentUrl) -Description 'Select PAC environment' | Out-Null
}

function Get-EnvironmentVariableValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $item = Get-Item -Path ("Env:{0}" -f $Name) -ErrorAction SilentlyContinue
    if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace($item.Value)) {
        return $item.Value.Trim()
    }

    return $null
}

function Resolve-AccessToken {
    param(
        [Parameter()][string]$ProvidedAccessToken,
        [Parameter(Mandatory = $true)][string]$ResolvedEnvironmentUrl
    )

    if (-not [string]::IsNullOrWhiteSpace($ProvidedAccessToken)) {
        return $ProvidedAccessToken.Trim()
    }

    foreach ($variableName in @('DATAVERSE_ACCESS_TOKEN', 'PAC_ACCESS_TOKEN')) {
        $value = Get-EnvironmentVariableValue -Name $variableName
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            Write-Info "Using access token from environment variable $variableName."
            return $value
        }
    }

    $az = Get-Command az -ErrorAction SilentlyContinue
    if ($null -ne $az) {
        if ($env:IDENTITY_ENDPOINT -or $env:MSI_ENDPOINT -or $env:AZURE_CLIENT_ID) {
            try {
                $loginArgs = @('login', '--identity')
                if (-not [string]::IsNullOrWhiteSpace($env:AZURE_CLIENT_ID)) {
                    $loginArgs += @('--username', $env:AZURE_CLIENT_ID)
                }
                & az @loginArgs 1>$null 2>$null
            }
            catch {
                Write-WarnMessage "Azure CLI managed-identity bootstrap failed: $_"
            }
        }

        try {
            $token = & az account get-access-token --resource $ResolvedEnvironmentUrl --query accessToken -o tsv 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($token)) {
                Write-Info 'Using Azure CLI access token for Dataverse Web API operations.'
                return $token.Trim()
            }
        }
        catch {
            Write-WarnMessage "Azure CLI access-token fallback was unavailable: $_"
        }
    }

    return $null
}

function Get-RefreshedDataverseToken {
    param([Parameter(Mandatory = $true)][string]$ResolvedEnvironmentUrl)

    $az = Get-Command az -ErrorAction SilentlyContinue
    if ($null -eq $az) {
        return $null
    }

    try {
        $token = & az account get-access-token --resource $ResolvedEnvironmentUrl --query accessToken -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($token)) {
            $script:ResolvedDataverseToken = $token.Trim()
            return $script:ResolvedDataverseToken
        }
    }
    catch {
        Write-WarnMessage "Azure CLI access-token refresh failed: $_"
    }

    return $null
}

function Get-DataverseHeaders {
    param([Parameter(Mandatory = $true)][string]$Token)

    return @{
        Authorization      = 'Bearer ' + $Token
        Accept             = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
        'Content-Type'     = 'application/json; charset=utf-8'
    }
}

function ConvertTo-ODataStringLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'{0}'" -f $Value.Replace("'", "''")
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory = $true)][string]$RelativeUri,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter()][object]$Body,
        [Parameter()][switch]$AllowNotFound
    )

    $uri = $script:BaseApiUrl + $RelativeUri.TrimStart('/')
    $effectiveToken = if (-not [string]::IsNullOrWhiteSpace($script:ResolvedDataverseToken)) { $script:ResolvedDataverseToken } else { $Token }
    $headers = Get-DataverseHeaders -Token $effectiveToken

    if ($DryRun -and $Method -ne 'GET') {
        Write-Info "[DRY RUN] $Method $uri"
        if ($Body) {
            Write-Info ((ConvertTo-Json $Body -Depth 20) -replace "`n", ' ')
        }

        return [pscustomobject]@{ StatusCode = 200; Body = @{}; Headers = @{} }
    }

    $bodyJson = $null
    if ($Body) {
        $bodyJson = $Body | ConvertTo-Json -Depth 20 -Compress
    }

    $response = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -Body $bodyJson -UseBasicParsing -SkipHttpErrorCheck
    if ($response.StatusCode -eq 401) {
        Write-Info "Dataverse token rejected (HTTP 401); refreshing via Azure CLI and retrying $Method $RelativeUri."
        $refreshed = Get-RefreshedDataverseToken -ResolvedEnvironmentUrl $EnvironmentUrl
        if ($refreshed) {
            $headers = Get-DataverseHeaders -Token $refreshed
            $response = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -Body $bodyJson -UseBasicParsing -SkipHttpErrorCheck
        }
    }
    if ($AllowNotFound -and $response.StatusCode -eq 404) {
        return $null
    }

    if ($response.StatusCode -ge 400) {
        throw "Dataverse Web API request failed ($Method $RelativeUri): HTTP $($response.StatusCode) $($response.Content)"
    }

    $responseBody = $null
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
        try {
            $responseBody = $response.Content | ConvertFrom-Json -AsHashtable
        }
        catch {
            $responseBody = $response.Content
        }
    }

    return [pscustomobject]@{
        StatusCode = [int]$response.StatusCode
        Body       = $responseBody
        Headers    = $response.Headers
    }
}

function Get-ExistingPublisher {
    param([Parameter(Mandatory = $true)][string]$Token)

    $prefixFilter = ConvertTo-ODataStringLiteral -Value $PublisherPrefix
    $nameFilter = ConvertTo-ODataStringLiteral -Value $PublisherName
    $relativeUri = "publishers?`$select=publisherid,uniquename,friendlyname,customizationprefix,customizationoptionvalueprefix&`$filter=customizationprefix eq $prefixFilter or uniquename eq $nameFilter"
    $response = Invoke-DataverseRequest -Method GET -RelativeUri $relativeUri -Token $Token
    if ($response.Body.value.Count -gt 0) {
        return $response.Body.value[0]
    }

    return $null
}

function New-PublisherRecord {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory = $true)][string]$Token)

    $body = @{
        friendlyname                   = $PublisherName
        uniquename                     = $PublisherName
        customizationprefix            = $PublisherPrefix
        customizationoptionvalueprefix = $PublisherOptionValuePrefix
        description                    = 'Publisher for the FSI Agent Intake unmanaged solution shell.'
        supportingwebsiteurl           = 'https://judeper.github.io/FSI-AgentGov-Solutions/'
    }

    if ($DryRun) {
        Write-Info "[DRY RUN] Would create publisher '$PublisherName'."
        return @{
            publisherid                    = '00000000-0000-0000-0000-000000000001'
            friendlyname                   = $PublisherName
            uniquename                     = $PublisherName
            customizationprefix            = $PublisherPrefix
            customizationoptionvalueprefix = $PublisherOptionValuePrefix
        }
    }

    if (-not $PSCmdlet.ShouldProcess($PublisherName, 'Create Dataverse publisher')) {
        return @{
            publisherid                    = '00000000-0000-0000-0000-000000000001'
            friendlyname                   = $PublisherName
            uniquename                     = $PublisherName
            customizationprefix            = $PublisherPrefix
            customizationoptionvalueprefix = $PublisherOptionValuePrefix
        }
    }

    $response = Invoke-DataverseRequest -Method POST -RelativeUri 'publishers' -Token $Token -Body $body
    $odataEntityId = $response.Headers['OData-EntityId']
    if (-not $odataEntityId) {
        throw 'Publisher creation did not return an OData-EntityId header.'
    }

    $match = [regex]::Match($odataEntityId, 'publishers\(([0-9a-fA-F-]+)\)')
    if (-not $match.Success) {
        throw "Unable to parse publisherid from '$odataEntityId'."
    }

    return @{
        publisherid                    = $match.Groups[1].Value
        friendlyname                   = $PublisherName
        uniquename                     = $PublisherName
        customizationprefix            = $PublisherPrefix
        customizationoptionvalueprefix = $PublisherOptionValuePrefix
    }
}

function Get-ExistingSolution {
    param([Parameter()][string]$Token)

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $solutionNameFilter = ConvertTo-ODataStringLiteral -Value $SolutionName
        $response = Invoke-DataverseRequest -Method GET -RelativeUri "solutions?`$select=solutionid,uniquename,friendlyname,version&`$filter=uniquename eq $solutionNameFilter" -Token $Token
        if ($response.Body.value.Count -gt 0) {
            return $response.Body.value[0]
        }

        return $null
    }

    $solutions = Invoke-PacCommand -Arguments @('solution', 'list', '--environment', $EnvironmentUrl, '--json') -Description 'Solution inventory' -ExpectJson
    foreach ($solution in @($solutions)) {
        $uniqueName = $solution.SolutionUniqueName
        if ([string]::IsNullOrWhiteSpace($uniqueName) -and $solution.PSObject.Properties['uniquename']) {
            $uniqueName = $solution.uniquename
        }

        if ($uniqueName -eq $SolutionName) {
            return $solution
        }
    }

    return $null
}

function New-SolutionRecord {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$PublisherId
    )

    $body = @{
        friendlyname             = $SolutionDisplayName
        uniquename               = $SolutionName
        version                  = $SolutionVersion
        description              = 'Unmanaged shell that holds the Agent Intake flows, connection references, environment variables, and Dataverse dependencies.'
        'publisherid@odata.bind' = "/publishers($PublisherId)"
    }

    if ($DryRun) {
        Write-Info "[DRY RUN] Would create solution '$SolutionName'."
        return @{
            solutionid   = '00000000-0000-0000-0000-000000000002'
            friendlyname = $SolutionDisplayName
            uniquename   = $SolutionName
            version      = $SolutionVersion
        }
    }

    if (-not $PSCmdlet.ShouldProcess($SolutionName, 'Create Dataverse solution')) {
        return @{
            solutionid   = '00000000-0000-0000-0000-000000000002'
            friendlyname = $SolutionDisplayName
            uniquename   = $SolutionName
            version      = $SolutionVersion
        }
    }

    $response = Invoke-DataverseRequest -Method POST -RelativeUri 'solutions' -Token $Token -Body $body
    $odataEntityId = $response.Headers['OData-EntityId']
    if (-not $odataEntityId) {
        throw 'Solution creation did not return an OData-EntityId header.'
    }

    $match = [regex]::Match($odataEntityId, 'solutions\(([0-9a-fA-F-]+)\)')
    if (-not $match.Success) {
        throw "Unable to parse solutionid from '$odataEntityId'."
    }

    return @{
        solutionid   = $match.Groups[1].Value
        friendlyname = $SolutionDisplayName
        uniquename   = $SolutionName
        version      = $SolutionVersion
    }
}

function Test-TableExistsWithPac {
    param([Parameter(Mandatory = $true)][string]$LogicalName)

    if ($DryRun) {
        return $true
    }

    $output = Invoke-PacCommand -Arguments @('model', 'list-tables', '--environment', $EnvironmentUrl, '--search', $LogicalName, '--type', 'custom') -Description "Table discovery for $LogicalName"
    return ($output -match [regex]::Escape($LogicalName))
}

function Add-SolutionComponent {
    param(
        [Parameter(Mandatory = $true)][string]$Component,
        [Parameter(Mandatory = $true)][int]$ComponentType,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter()][switch]$AddRequiredComponents
    )

    $arguments = @(
        'solution',
        'add-solution-component',
        '--environment', $EnvironmentUrl,
        '--solutionUniqueName', $SolutionName,
        '--component', $Component,
        '--componentType', [string]$ComponentType
    )

    if ($AddRequiredComponents) {
        $arguments += '--AddRequiredComponents'
    }

    try {
        Invoke-PacCommand -Arguments $arguments -Description $Description | Out-Null
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match 'already' -or $message -match 'exists in solution' -or $message -match 'has already been added') {
            Write-Info "$Description is already in the solution."
            return
        }

        throw
    }
}

function Get-ExistingEnvironmentVariableDefinition {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$SchemaName
    )

    $filter = ConvertTo-ODataStringLiteral -Value $SchemaName
    $response = Invoke-DataverseRequest -Method GET -RelativeUri "environmentvariabledefinitions?`$select=environmentvariabledefinitionid,schemaname,displayname,description,defaultvalue,type&`$filter=schemaname eq $filter" -Token $Token
    if ($response.Body.value.Count -gt 0) {
        return $response.Body.value[0]
    }

    return $null
}

function Get-ExistingEnvironmentVariableValue {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$SchemaName
    )

    $valueSchemaName = ConvertTo-ODataStringLiteral -Value ("{0}_value" -f $SchemaName)
    $response = Invoke-DataverseRequest -Method GET -RelativeUri "environmentvariablevalues?`$select=environmentvariablevalueid,schemaname,value&`$filter=schemaname eq $valueSchemaName" -Token $Token
    if ($response.Body.value.Count -gt 0) {
        return $response.Body.value[0]
    }

    return $null
}

function Sync-EnvironmentVariable {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Definition,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $schemaName = $Definition.SchemaName
    $existingDefinition = Get-ExistingEnvironmentVariableDefinition -Token $Token -SchemaName $schemaName

    if ($DryRun) {
        if ($null -eq $existingDefinition) {
            $definitionId = '00000000-0000-0000-0000-000000000100'
            Write-Info "[DRY RUN] Would create environment-variable definition $schemaName."
            Add-SummaryRow -Area 'Environment variable' -Status 'Planned create' -Detail $schemaName
        }
        else {
            $definitionId = $existingDefinition.environmentvariabledefinitionid
            Write-Info "[DRY RUN] Would update environment-variable definition $schemaName."
            Add-SummaryRow -Area 'Environment variable' -Status 'Planned update' -Detail $schemaName
        }

        Add-SolutionComponent -Component $definitionId -ComponentType 380 -Description "Add environment variable $schemaName to solution"

        if ($null -ne $EnvVarValues -and $EnvVarValues.ContainsKey($schemaName)) {
            $existingValue = Get-ExistingEnvironmentVariableValue -Token $Token -SchemaName $schemaName
            $valueStatus = if ($null -eq $existingValue) { 'Planned create' } elseif ($existingValue.value -ne [string]$EnvVarValues[$schemaName]) { 'Planned update' } else { 'Unchanged' }
            Add-SummaryRow -Area 'Environment variable value' -Status $valueStatus -Detail $schemaName
        }

        return
    }

    if ($null -eq $existingDefinition) {
        $body = @{
            schemaname   = $schemaName
            displayname  = $Definition.DisplayName
            description  = $Definition.Description
            defaultvalue = [string]$Definition.DefaultValue
            type         = [int]$Definition.Type
        }

        $response = Invoke-DataverseRequest -Method POST -RelativeUri 'environmentvariabledefinitions' -Token $Token -Body $body
        $odataEntityId = $response.Headers['OData-EntityId']
        $match = [regex]::Match($odataEntityId, 'environmentvariabledefinitions\(([0-9a-fA-F-]+)\)')
        if (-not $match.Success) {
            throw "Unable to parse environmentvariabledefinitionid from '$odataEntityId'."
        }

        $definitionId = $match.Groups[1].Value
        Write-Info "Created environment-variable definition $schemaName."
        Add-SummaryRow -Area 'Environment variable' -Status 'Created' -Detail $schemaName
    }
    else {
        $definitionId = $existingDefinition.environmentvariabledefinitionid
        $patch = @{
            displayname  = $Definition.DisplayName
            description  = $Definition.Description
            defaultvalue = [string]$Definition.DefaultValue
            type         = [int]$Definition.Type
        }
        Invoke-DataverseRequest -Method PATCH -RelativeUri ("environmentvariabledefinitions({0})" -f $definitionId) -Token $Token -Body $patch | Out-Null
        Write-Info "Updated environment-variable definition $schemaName."
        Add-SummaryRow -Area 'Environment variable' -Status 'Updated' -Detail $schemaName
    }

    Add-SolutionComponent -Component $definitionId -ComponentType 380 -Description "Add environment variable $schemaName to solution"

    if ($null -eq $EnvVarValues -or -not $EnvVarValues.ContainsKey($schemaName)) {
        return
    }

    $desiredValue = [string]$EnvVarValues[$schemaName]
    $existingValue = Get-ExistingEnvironmentVariableValue -Token $Token -SchemaName $schemaName
    if ($null -eq $existingValue) {
        $body = @{
            schemaname = "{0}_value" -f $schemaName
            value      = $desiredValue
            'EnvironmentVariableDefinitionId@odata.bind' = "/environmentvariabledefinitions($definitionId)"
        }
        Invoke-DataverseRequest -Method POST -RelativeUri 'environmentvariablevalues' -Token $Token -Body $body | Out-Null
        Write-Info "Created current value for $schemaName."
        Add-SummaryRow -Area 'Environment variable value' -Status 'Created' -Detail $schemaName
        return
    }

    if ($existingValue.value -ne $desiredValue) {
        Invoke-DataverseRequest -Method PATCH -RelativeUri ("environmentvariablevalues({0})" -f $existingValue.environmentvariablevalueid) -Token $Token -Body @{ value = $desiredValue } | Out-Null
        Write-Info "Updated current value for $schemaName."
        Add-SummaryRow -Area 'Environment variable value' -Status 'Updated' -Detail $schemaName
        return
    }

    Add-SummaryRow -Area 'Environment variable value' -Status 'Unchanged' -Detail $schemaName
}

function Resolve-ConnectorIdPath {
    param([Parameter(Mandatory = $true)][string]$ConnectorApiId)

    if ($ConnectorApiId.StartsWith('/providers/', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $ConnectorApiId
    }

    return "/providers/Microsoft.PowerApps/apis/{0}" -f $ConnectorApiId
}

function Get-ExistingConnectionReference {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$LogicalName
    )

    $filter = ConvertTo-ODataStringLiteral -Value $LogicalName
    $relativeUri = "connectionreferences?`$select=connectionreferenceid,connectionreferencelogicalname,connectionreferencedisplayname,connectorid,description,promptingbehavior&`$filter=connectionreferencelogicalname eq $filter"
    $response = Invoke-DataverseRequest -Method GET -RelativeUri $relativeUri -Token $Token
    if ($response.Body.value.Count -gt 0) {
        return $response.Body.value[0]
    }

    return $null
}

function Sync-ConnectionReference {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Definition,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $logicalName = $Definition.LogicalName
    $connectorPath = Resolve-ConnectorIdPath -ConnectorApiId $Definition.ConnectorApiId
    $existing = Get-ExistingConnectionReference -Token $Token -LogicalName $logicalName

    if ($DryRun) {
        if ($null -eq $existing) {
            $connectionReferenceId = '00000000-0000-0000-0000-000000000200'
            Write-Info "[DRY RUN] Would create connection reference $logicalName."
            Add-SummaryRow -Area 'Connection reference' -Status 'Planned create' -Detail $logicalName
        }
        else {
            $connectionReferenceId = $existing.connectionreferenceid
            Write-Info "[DRY RUN] Would update connection reference $logicalName."
            Add-SummaryRow -Area 'Connection reference' -Status 'Planned update' -Detail $logicalName
        }

        Add-SolutionComponent -Component $connectionReferenceId -ComponentType 371 -Description "Add connection reference $logicalName to solution"
        return
    }

    if ($null -eq $existing) {
        $body = @{
            connectionreferencelogicalname = $logicalName
            connectionreferencedisplayname = $Definition.DisplayName
            connectorid                    = $connectorPath
            description                    = $Definition.Description
            promptingbehavior              = 0
        }

        $response = Invoke-DataverseRequest -Method POST -RelativeUri 'connectionreferences' -Token $Token -Body $body
        $odataEntityId = $response.Headers['OData-EntityId']
        $match = [regex]::Match($odataEntityId, 'connectionreferences\(([0-9a-fA-F-]+)\)')
        if (-not $match.Success) {
            throw "Unable to parse connectionreferenceid from '$odataEntityId'."
        }

        $connectionReferenceId = $match.Groups[1].Value
        Write-Info "Created connection reference $logicalName."
        Add-SummaryRow -Area 'Connection reference' -Status 'Created' -Detail $logicalName
    }
    else {
        $connectionReferenceId = $existing.connectionreferenceid
        $patch = @{
            connectionreferencedisplayname = $Definition.DisplayName
            connectorid                    = $connectorPath
            description                    = $Definition.Description
            promptingbehavior              = 0
        }
        Invoke-DataverseRequest -Method PATCH -RelativeUri ("connectionreferences({0})" -f $connectionReferenceId) -Token $Token -Body $patch | Out-Null
        Write-Info "Updated connection reference $logicalName."
        Add-SummaryRow -Area 'Connection reference' -Status 'Updated' -Detail $logicalName
    }

    Add-SolutionComponent -Component $connectionReferenceId -ComponentType 371 -Description "Add connection reference $logicalName to solution"
}

if (-not (Test-PacInstalled)) {
    throw 'PAC CLI was not found on PATH. Install Microsoft.PowerApps.CLI.Tool before running this script.'
}

$pacVersion = Get-PacVersion
Add-SummaryRow -Area 'PAC CLI' -Status 'Detected' -Detail $pacVersion

Test-PacAuthentication
Select-PacEnvironment

$resolvedToken = Resolve-AccessToken -ProvidedAccessToken $AccessToken -ResolvedEnvironmentUrl $EnvironmentUrl
if ([string]::IsNullOrWhiteSpace($resolvedToken)) {
    Write-WarnMessage 'No Dataverse access token was resolved. PAC CLI solution actions can continue, but publisher/solution bootstrap, environment-variable upserts, and connection-reference upserts require Azure CLI cached auth, DATAVERSE_ACCESS_TOKEN, or -AccessToken.'
}
$script:ResolvedDataverseToken = $resolvedToken

$solutionRecord = Get-ExistingSolution -Token $resolvedToken
if ($null -eq $solutionRecord) {
    if ([string]::IsNullOrWhiteSpace($resolvedToken)) {
        if ($DryRun) {
            Write-WarnMessage 'Dry run could not verify publisher or solution existence because no Dataverse access token was available.'
            Add-SummaryRow -Area 'Publisher' -Status 'Not verified (dry run)' -Detail $PublisherName
            Add-SummaryRow -Area 'Solution' -Status 'Not verified (dry run)' -Detail $SolutionName
        }
        else {
            throw "Solution '$SolutionName' does not exist and could not be created because no Dataverse access token was available. Provide -AccessToken, DATAVERSE_ACCESS_TOKEN, or Azure CLI auth for the first bootstrap run."
        }
    }
    else {
        $publisherRecord = Get-ExistingPublisher -Token $resolvedToken
        if ($null -eq $publisherRecord) {
            Write-Info "Publisher '$PublisherName' was not found. Creating it now."
            $publisherRecord = New-PublisherRecord -Token $resolvedToken
            Add-SummaryRow -Area 'Publisher' -Status $(if ($DryRun) { 'Planned create' } else { 'Created' }) -Detail $PublisherName
        }
        else {
            Write-Info "Using existing publisher '$($publisherRecord.friendlyname)'."
            Add-SummaryRow -Area 'Publisher' -Status 'Existing' -Detail $publisherRecord.friendlyname
        }

        Write-Info "Creating solution '$SolutionName'."
        $solutionRecord = New-SolutionRecord -Token $resolvedToken -PublisherId $publisherRecord.publisherid
        Add-SummaryRow -Area 'Solution' -Status $(if ($DryRun) { 'Planned create' } else { 'Created' }) -Detail $SolutionName
    }
}
else {
    Write-Info "Using existing solution '$SolutionName'."
    Add-SummaryRow -Area 'Solution' -Status 'Existing' -Detail $SolutionName
}

$missingTables = New-Object System.Collections.Generic.List[string]
foreach ($table in $tableSpecs) {
    if (-not (Test-TableExistsWithPac -LogicalName $table.LogicalName)) {
        $missingTables.Add($table.LogicalName) | Out-Null
        Add-SummaryRow -Area 'Table' -Status 'Missing' -Detail $table.LogicalName
        continue
    }

    Add-SolutionComponent -Component $table.SchemaName -ComponentType 1 -AddRequiredComponents -Description "Add $($table.DisplayName) table to solution"
    Add-SummaryRow -Area 'Table' -Status $(if ($DryRun) { 'Planned add' } else { 'Registered' }) -Detail $table.LogicalName
}

if ($missingTables.Count -gt 0) {
    Add-ManualStep ('Run python .\scripts\create_fsi_intake_dataverse_schema.py against {0} before retrying the shell bootstrap. Missing tables: {1}' -f $EnvironmentUrl, ($missingTables -join ', '))
}

foreach ($optionSetName in $optionSetNames) {
    Add-SolutionComponent -Component $optionSetName -ComponentType 9 -Description "Add option set $optionSetName to solution"
    Add-SummaryRow -Area 'Option set' -Status $(if ($DryRun) { 'Planned add' } else { 'Registered' }) -Detail $optionSetName
}

if (-not [string]::IsNullOrWhiteSpace($resolvedToken)) {
    foreach ($definition in $envVarDefinitions) {
        Sync-EnvironmentVariable -Definition $definition -Token $resolvedToken
    }

    foreach ($definition in $connectionReferenceDefinitions) {
        Sync-ConnectionReference -Definition $definition -Token $resolvedToken
    }

    if (-not [string]::IsNullOrWhiteSpace($GraphCustomConnectorApiId)) {
        Sync-ConnectionReference -Definition @{
            LogicalName  = 'fsi_cr_graph_agentintake'
            DisplayName  = 'Microsoft Graph - Agent Intake'
            ConnectorApiId = $GraphCustomConnectorApiId
            Description  = 'Microsoft Graph custom-connector reference used when the tenant prefers a solution-aware connector over raw HTTP actions.'
        } -Token $resolvedToken
    }
    else {
        Add-ManualStep 'Create the Microsoft Graph custom connector, then rerun this script with -GraphCustomConnectorApiId <shared_customConnectorId> so the Graph connection reference can be created and added to the solution.'
    }
}
else {
    Add-ManualStep 'Bind Azure CLI auth or provide -AccessToken so the script can create or update environment variables.'
    Add-ManualStep 'Bind Azure CLI auth or provide -AccessToken so the script can create or update connection references.'
    Add-ManualStep 'Create the Microsoft Graph custom connector and the fsi_cr_graph_agentintake connection reference in the maker UI if you are not rerunning with -GraphCustomConnectorApiId.'
}

Invoke-PacCommand -Arguments @('solution', 'publish', '--environment', $EnvironmentUrl) -Description 'Publish customizations' | Out-Null
Add-SummaryRow -Area 'Publish' -Status $(if ($DryRun) { 'Planned' } else { 'Completed' }) -Detail $SolutionName

Write-Host ''
Write-Host '=== Agent Intake solution shell summary ===' -ForegroundColor Green
$script:SummaryRows | Sort-Object Area, Detail | Format-Table -AutoSize

Write-Host ''
Write-Host ('PAC CLI version : {0}' -f $pacVersion)
Write-Host ('Solution        : {0} ({1})' -f $SolutionDisplayName, $SolutionName)
Write-Host ('Environment     : {0}' -f $EnvironmentUrl)
Write-Host ('Tables          : {0}' -f $tableSpecs.Count)
Write-Host ('Option sets     : {0}' -f $optionSetNames.Count)
Write-Host ('Env vars        : {0}' -f $envVarDefinitions.Count)
Write-Host ('Conn refs       : {0}' -f ($connectionReferenceDefinitions.Count + 1))

Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Green
Write-Host '1. Open Solutions > FSI Agent Intake > Connection references and bind each reference to a working connection.'
Write-Host '2. Populate current values for every environment variable that was created without a supplied -EnvVarValues entry.'
Write-Host '3. Review agent-intake\docs\flow-build-prerequisites.md and then build the flows in agent-intake\docs\flow-configuration.md.'
Write-Host '4. Run the smoke test and the Power Automate flow checks after the flows are built.'

if ($script:ManualSteps.Count -gt 0) {
    Write-Host ''
    Write-Host 'Outstanding manual steps:' -ForegroundColor Yellow
    foreach ($step in $script:ManualSteps) {
        Write-Host ('- {0}' -f $step)
    }
}

Write-Host ''
Write-Host 'PAC CLI commands used:' -ForegroundColor Green
foreach ($command in $script:PacCommandsUsed) {
    Write-Host ('- {0}' -f $command)
}
